// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./IERC7583Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "contracts/lib/Struct.sol";
import "contracts/lib/Enum.sol";

import "hardhat/console.sol";

contract InscriptionMarket_v2 is
    OwnableUpgradeable,
    EIP712Upgradeable,
    OrderParameterBase,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public feeReceiver;

    // 100 / 10000
    uint256 public feeRate;

    // offerer => counter
    mapping(address => uint256) public counters;
    // order hash => status
    mapping(bytes32 => uint256) public orderStatus;

    event OrderCancelled(address indexed canceller, bytes32 indexed salt);
    event Sold(
        bytes32 indexed orderHash,
        uint256 indexed time,
        address from,
        address to,
        uint256 price
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
    /* 
        - Cancellation verification can be performed proactively on-chain.
        - Zone is essentially a logic similar to a signature machine.
        - Conduit provides a way for the project party to manage authorization.

        Criteria can be used to place multiple NFTs in a single order, and Advanced methods are required to facilitate partial fulfillment. If Criteria is set to 0, any tokenId owned by the user can be fulfilled without further verification of its inclusion in the order.

        The Advanced method allows specifying the recipient address for the NFT.
     */

    function _verify(
        bytes32 orderHash,
        bytes calldata signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(orderHash);
        address signer = ECDSAUpgradeable.recover(digest, signature);
        return (signer);
    }

    /// @notice The entire order is executed at once, which can be either selling an NFT or offering tokens to purchase an NFT. 
    /// @notice Transaction Scenario: Used when trading artwork, INSC's savings jar, and ORUS's engraved NFT.
    /// @notice The offer at this point is not for the FT (fungible token), but for a specific tokenId.
    // TODO: Support users to place multiple NFTs in a single order at once.
    function fulfillOrder(
        OrderParameters calldata order
    ) external payable nonReentrant {
        address from;
        address to;
        // calculate order hash
        bytes32 orderHash = _deriveOrderHash_NotArray(order, counters[order.offerer]);
        console.logBytes32(orderHash);

        bytes32 orderHash_ = _deriveOrderHash(order, counters[order.offerer]);
        console.logBytes32(orderHash_);

        require(
            block.timestamp >= order.startTime &&
                block.timestamp <= order.endTime,
            "Time error"
        );

        OfferItem memory offerItem = order.offer[0];

        require(
            orderStatus[orderHash] < offerItem.startAmount,
            "Order filled or canceled"
        );

        // verify signature
        require(
            _verify(orderHash, order.signature) == order.offerer,
            "Sign error"
        );

        // transfer fee
        uint256 _serviceFee;

        ConsiderationItem memory consideration = order.consideration[0];
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
                offerItem.itemType != ItemType.ERC721
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
            consideration.itemType == ItemType.ERC721
        ) {
            if (offerItem.itemType != ItemType.ERC20) {
                // other offer type is not support
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }
            IERC7583Upgradeable(consideration.token).safeTransferFrom(
                msg.sender,
                consideration.recipient,
                consideration.identifierOrCriteria
            );

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
                consideration.itemType != ItemType.ERC721
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
            offerItem.itemType == ItemType.ERC721
        ) {
            IERC7583Upgradeable(offerItem.token).safeTransferFrom(
                order.offerer,
                msg.sender,
                offerItem.identifierOrCriteria
            );

            from = order.offerer;
            to = msg.sender;
        } else {
            // other offer type is not support
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        orderStatus[orderHash] = offerItem.startAmount;

        emit Sold(orderHash, block.timestamp, from, to, price);
    }

    // TODO: 
    /// @notice To complete multiple transactions at once, such as purchasing multiple NFTs or accepting multiple offers, the concept of an aggregator is required.
    // How to bypass failed NFTs
    // How to save gas
    // Whether to support simultaneous transactions of NFTs from different collections is not required.
    function multipleFillOrder(
        OrderParameters[] calldata orders
    ) external payable nonReentrant {

    }

    // TODO: 
    /// @notice Partial fulfillment in a single transaction without transferring NFTs, only purchasing a portion of the FTs.
    function partialFillOrder(
        OrderParameters calldata order
    ) external payable nonReentrant {
       
    }

    /// @notice Accept the offer for FT and it is a large order, where the sum of the FT quantities in multiple NFTs does not exceed the quantity of this offer.
    function takeOffer(
        OrderParameters calldata order, address considerationAddr, uint256[] calldata insIds
    ) external payable nonReentrant {
        // calculate order hash
        bytes32 orderHash = _deriveOrderHash(order, counters[order.offerer]);
        require(
            block.timestamp >= order.startTime &&
                block.timestamp <= order.endTime,
            "Time error"
        );

        OfferItem memory offerItem = order.offer[0];
        ConsiderationItem memory consideration = order.consideration[0];

        require(
            orderStatus[orderHash] < offerItem.startAmount,
            "Order filled or canceled"
        );

        require(consideration.identifierOrCriteria == type(uint256).max && consideration.token == considerationAddr, "Params error");

        // verify signature
        require(
            _verify(orderHash, order.signature) == order.offerer,
            "Sign error"
        );

        if (offerItem.itemType != ItemType.ERC20 && consideration.itemType != ItemType.ERC721) {
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        uint256 price;
        for (uint256 i; i < insIds.length; i++) {
            uint256 insId = insIds[i];

            require(msg.sender == IERC7583Upgradeable(considerationAddr).ownerOf(insId), "Is not yours");

            price += IERC7583Upgradeable(considerationAddr).balanceOfIns(insId) * offerItem.endAmount;
            
            IERC7583Upgradeable(considerationAddr).safeTransferFrom(
                msg.sender,
                consideration.recipient,
                insId
            );
        }

        require (price < offerItem.startAmount - orderStatus[orderHash], "Insufficient value");

        uint256 _serviceFee = (price * feeRate) / 10000;
        IERC20Upgradeable(offerItem.token).safeTransferFrom(
            order.offerer,
            feeReceiver,
            _serviceFee
        );
        IERC20Upgradeable(offerItem.token).safeTransferFrom(
            order.offerer,
            msg.sender,
            price - _serviceFee
        );

        orderStatus[orderHash] += price;

        emit Sold(orderHash, block.timestamp, msg.sender, consideration.recipient, price);
    }

    // TODO: 
    /// @notice Accept multiple offers for FT, where the prices of these offers may vary.
    function takeOffers(
        OrderParameters[] calldata orders, address considerationAddr, uint256 insId
    ) external payable nonReentrant {
    }

    // TODO: 
    /// @notice for market makers
    function matchOrders(
        OrderParameters[] calldata lists, OrderParameters[] calldata offers
    ) external payable nonReentrant {
    }

    /* function fulfillOrderOffer(
        OrderParameters[] calldata orders, address considerationAddr, uint256 insId
    ) external payable nonReentrant {
        require(msg.sender == IERC7583Upgradeable(considerationAddr).ownerOf(insId), "Is not yours");

        for (uint256 i; i < orders.length; i++) {
            OrderParameters order = orders[i];

            // calculate order hash
            bytes32 orderHash = _deriveOrderHash(order, counters[order.offerer]);
            require(
                block.timestamp >= order.startTime &&
                    block.timestamp <= order.endTime,
                "Time error"
            );

            OfferItem memory offerItem = order.offer[0];
            ConsiderationItem memory consideration = order.consideration[0];

            require(
                orderStatus[orderHash] < offerItem.startAmount,
                "Order filled or canceled"
            );

            require(consideration.identifierOrCriteria == type(uint256).max && consideration.token == considerationAddr, "Params error");

            // verify signature
            require(
                _verify(orderHash, order.signature) == order.offerer,
                "Sign error"
            );

            if (offerItem.itemType != ItemType.ERC20 && consideration.itemType != ItemType.ERC721) {
                // ETH can't approve, offer's type cann't be NATIVE
                revert OrderTypeError(offerItem.itemType, consideration.itemType);
            }

            // transfer fee
            uint256 _serviceFee;
            uint256 price;
            uint256 balanceOfIns = IERC7583Upgradeable(considerationAddr).balanceOfIns(insId);

            if (balanceOfIns * offerItem.endAmount > offerItem.startAmount) {
                
            }
            
            IERC7583Upgradeable(consideration.token).safeTransferFrom(
                msg.sender,
                consideration.recipient,
                consideration.identifierOrCriteria
            );


            // Offer
                
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

            orderStatus[orderHash] = offerItem.startAmount;

            emit Sold(orderHash, order.salt, block.timestamp, msg.sender, to, price);
        }
    } */

    function cancel(OrderComponents[] calldata orders) external nonReentrant {
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
            orderStatus[orderHash] = order.offer[0].startAmount;

            // Emit an event signifying that the order has been cancelled.
            emit OrderCancelled(offerer, orderHash);

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
