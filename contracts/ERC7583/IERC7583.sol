// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ERC-7583 Inscription Standard in Smart Contracts
interface IERC7583 {
  event Inscribe(uint256 indexed id, bytes data);
}