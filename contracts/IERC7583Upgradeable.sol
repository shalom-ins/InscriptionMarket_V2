// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

/**
 * @title ERC-7583 Inscription Standard in Smart Contracts 
 * 
 * Note: the ERC-165 identifier for this interface is 0x4644c7dc.
 */
interface IERC7583Upgradeable is IERC20Upgradeable, IERC165Upgradeable{
    /**
     * @dev Emitted when `value` fungible tokens of inscriptions are moved from one inscription (`from`) to
     * another (`to`).
     *
     * Note that `value` MAY be zero.
     */
    event TransferInsToIns(uint256 indexed fromIns, uint256 indexed toIns, uint256 value);

	  /**
     * @dev Emitted when `inscriptionId` inscription is transferred from `from` to `to`.
     */
    event TransferIns(address indexed from, address indexed to, uint256 indexed inscriptionId);

	  /**
     * @dev Emitted when `owner` enables `approved` to manage the `insId` inscription.
     */
    event ApprovalIns(address indexed owner, address indexed approved, uint256 indexed insId);

	  /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its inscriptions.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the amount of inscriptions owned by `account`.
     */
    function insBalance(address account) external view returns (uint256);

	  /**
     * @dev Returns the value of fungible tokens in the inscription(`indId`).
     */
    function balanceOfIns(uint256 insId) external view returns (uint256);

	  /**
     * @dev Returns the owner of the `insId` inscription.
     *
     * Requirements:
     *
     * - `insId` MUST exist.
     */
    function ownerOf(uint256 insId) external view returns (address owner);

	  /**
     * @dev Gives permission to `to` to transfer `insId` inscription to another account.
     * The approval is cleared when the inscription is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller MUST own the inscription or be an approved operator.
     * - `insId` MUST exist.
     *
     * Emits an {ApprovalIns} event.
     */
    function approveIns(address to, uint256 insId) external returns (bool);

	  /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferInsFrom} or {safeTransferFrom} for any inscription owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` MUST NOT the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

	  /**
     * @dev Returns the account approved for `insId` inscription.
     *
     * Requirements:
     *
     * - `insId` MUST exist.
     */
    function getApproved(uint256 insId) external view returns (address operator);

	  /**
     * @dev Returns if the `operator` is allowed to manage all of the inscriptions of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

	  /**
     * @dev Transfers `insId` inscription from `from` to `to`.
     *
     * WARNING: Note that the caller MUST confirm that the recipient is capable of receiving inscription
     * or else they MAY be permanently lost. Usage of {safeTransferFrom} SHOULD prevents loss, though the caller MUST
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` MUST NOT the zero address.
     * - `to` MUST NOT the zero address.
     * - `insId` inscription MUST be owned by `from`.
     * - If the caller is not `from`, it MUST be approved to move this inscription by either {approveIns} or {setApprovalForAll}.
     *
     * Emits a {TransferIns} event.
     */
    function transferInsFrom(address from, address to, uint256 insId) external;

    /**
     * @dev Safely transfers `insId` inscription from `from` to `to`, checking first that contract recipients
     * are aware of the ERC-7583 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` MUST NOT the zero address.
     * - `to` MUST NOT the zero address.
     * - `insId` token MUST exist and be owned by `from`.
     * - If the caller is not `from`, it MUST have been allowed to move this token by either {approveIns} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it MUST implement {IERC7583Receiver-onERC7583Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {TransferIns} event.
     */
    function safeTransferFrom(address from, address to, uint256 insId) external;
}