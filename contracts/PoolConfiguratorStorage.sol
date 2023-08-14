// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IPoolConfiguratorStorage } from "./interfaces/pool/IPoolConfiguratorStorage.sol";

abstract contract PoolConfiguratorStorage is IPoolConfiguratorStorage {
    uint256 internal _locked;

    address public override poolAdmin;
    address public override pendingPoolAdmin;

    address public override asset;
    address public override pool;

    uint256 public poolCover;

    bool public override active;
    bool public override configured;
    bool public override openToPublic;

    uint256 public override liquidityCap;
    uint256 public override adminFeeRate;

    mapping(address => bool) public override isBorrower;
    mapping(address => bool) public override isLender;
}
