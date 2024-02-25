// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "contracts/lib/Struct.sol";
import "contracts/lib/Enum.sol";

contract InscriptionMarket_v1 is
    OwnableUpgradeable,
    EIP712Upgradeable,
    OrderParameterBase,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct OrderStatus {
        bool isValidated;
        bool isCancelled;
    }

    address public feeReceiver;

    // 100 / 10000
    uint256 public feeRate;

    // offerer => counter
    mapping(address => uint256) public counters;
    // order hash => status
    mapping(bytes32 => OrderStatus) public orderStatus;

    event OrderCancelled(address indexed canceller, uint256 indexed salt);
    event Sold(
        bytes32 indexed orderHash,
        uint256 indexed salt,
        uint256 indexed time,
        address from,
        address to
    );
    event SetFee(address feeReceiver, uint256 feeRate);
    event CounterIncremented(uint256 indexed counter, address indexed user);

    error OrderTypeError(ItemType offerType, ItemType considerationType);
    error InvalidCanceller();

    function initialize(
        string memory name,
        string memory version
    ) public initializer {
        __Ownable_init();
        __EIP712_init(name, version);
    }

    function _verify(
        bytes32 orderHash,
        bytes calldata signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(orderHash);
        address signer = ECDSAUpgradeable.recover(digest, signature);
        return (signer);
    }

    function fulfillOrder(
        OrderParameters calldata order
    ) external payable nonReentrant {
        address from;
        address to;
        // calculate order hash
        bytes32 orderHash = _deriveOrderHash(order, counters[order.offerer]);

        require(
            block.timestamp >= order.startTime &&
                block.timestamp <= order.endTime,
            "Time error"
        );

        OrderStatus storage _orderStatus = orderStatus[orderHash];
        require(
            !_orderStatus.isCancelled && !_orderStatus.isValidated,
            "Status error"
        );

        // verify signature
        require(
            _verify(orderHash, order.signature) == order.offerer,
            "Sign error"
        );

        require(
            order.consideration.length == 1 && order.offer.length == 1,
            "Param length error"
        );

        // transfer fee
        uint256 _serviceFee;

        ConsiderationItem memory consideration = order.consideration[0];
        OfferItem memory offerItem = order.offer[0];
        if (offerItem.itemType == ItemType.NATIVE) {
            // ETH can't approve, offer's type cann't be NATIVE
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        uint256 price;
        // Consideration
        if (
            consideration.itemType == ItemType.NATIVE ||
            consideration.itemType == ItemType.ERC20
        ) {
            // check offer type, NATIVE/ERC20 <-> ERC721/ERC1155
            if (
                offerItem.itemType != ItemType.ERC721 &&
                offerItem.itemType != ItemType.ERC1155
            ) {
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }

            _serviceFee = (consideration.startAmount * feeRate) / 10000;
            price = consideration.startAmount;
            if (consideration.itemType == ItemType.NATIVE) {
                require(
                    msg.value >= consideration.startAmount,
                    "TX value error"
                );
                payable(feeReceiver).transfer(_serviceFee);
                unchecked {
                    payable(consideration.recipient).transfer(
                        consideration.startAmount - _serviceFee
                    );
                }
            } else if (consideration.itemType == ItemType.ERC20) {
                IERC20Upgradeable(consideration.token).safeTransferFrom(
                    msg.sender,
                    feeReceiver,
                    _serviceFee
                );
                IERC20Upgradeable(consideration.token).safeTransferFrom(
                    msg.sender,
                    consideration.recipient,
                    consideration.startAmount - _serviceFee
                );
            }
        } else if (
            consideration.itemType == ItemType.ERC721 ||
            consideration.itemType == ItemType.ERC1155
        ) {
            if (offerItem.itemType != ItemType.ERC20) {
                // other offer type is not support
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }
            if (consideration.itemType == ItemType.ERC721) {
                IERC721Upgradeable(consideration.token).safeTransferFrom(
                    msg.sender,
                    consideration.recipient,
                    consideration.identifierOrCriteria
                );
            }

            from = msg.sender;
            to = consideration.recipient;
        } else {
            // other consideration type is not support
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        // Offer
        if (offerItem.itemType == ItemType.ERC20) {
            // check consideration type
            if (
                consideration.itemType != ItemType.ERC721 &&
                consideration.itemType != ItemType.ERC1155
            ) {
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }
            _serviceFee = (offerItem.startAmount * feeRate) / 10000;
            price = offerItem.startAmount;
            IERC20Upgradeable(offerItem.token).safeTransferFrom(
                order.offerer,
                feeReceiver,
                _serviceFee
            );
            IERC20Upgradeable(offerItem.token).safeTransferFrom(
                order.offerer,
                msg.sender,
                offerItem.startAmount - _serviceFee
            );
        } else if (
            offerItem.itemType == ItemType.ERC721 ||
            offerItem.itemType == ItemType.ERC1155
        ) {
            if (offerItem.itemType == ItemType.ERC721) {
                IERC721Upgradeable(offerItem.token).safeTransferFrom(
                    order.offerer,
                    msg.sender,
                    offerItem.identifierOrCriteria
                );
            }

            from = order.offerer;
            to = msg.sender;
        } else {
            // other offer type is not support
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        _orderStatus.isValidated = true;

        emit Sold(orderHash, order.salt, block.timestamp, from, to);
    }

    function cancel(OrderComponents[] calldata orders) external nonReentrant {
        OrderStatus storage _orderStatus;
        address offerer;

        for (uint256 i = 0; i < orders.length; ) {
            // Retrieve the order.
            OrderComponents calldata order = orders[i];

            offerer = order.offerer;

            // Ensure caller is either offerer or zone of the order.
            if (msg.sender != offerer) {
                revert InvalidCanceller();
            }

            // Derive order hash using the order parameters and the counter.
            bytes32 orderHash = _deriveOrderHash(
                OrderParameters(
                    offerer,
                    order.offer,
                    order.consideration,
                    order.startTime,
                    order.endTime,
                    order.salt,
                    order.signature
                ),
                order.counter
            );

            // Retrieve the order status using the derived order hash.
            _orderStatus = orderStatus[orderHash];

            // Update the order status as not valid and cancelled.
            _orderStatus.isValidated = false;
            _orderStatus.isCancelled = true;

            // Emit an event signifying that the order has been cancelled.
            emit OrderCancelled(offerer, order.salt);

            // Increment counter inside body of loop for gas efficiency.
            ++i;
        }
    }

    function setFees(uint256 fee, address receiver) public onlyOwner {
        require(receiver != address(0), "fee receiver is empty");
        require(fee < 10000, "exceed max fee");
        feeReceiver = receiver;
        feeRate = fee;
        emit SetFee(receiver, fee);
    }
}
