// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import {IPoolConfigurator, ConfiguratorInputTypes, IACLManager} from 'aave-address-book/AaveV3.sol';
import {AaveV3Avalanche} from 'aave-address-book/AaveAddressBook.sol';
import {AaveV3AvaMIMATICListingSteward} from '../contracts/mimatic/AaveV3AvaMIMATICListingSteward.sol';
import {AaveV3Helpers, ReserveConfig, ReserveTokens, IERC20} from './helpers/AaveV3Helpers.sol';

contract MIMATICAaveV3AvaListingByGuardian is Test {
    using stdStorage for StdStorage;

    address public constant GUARDIAN_AVALANCHE =
        0xa35b76E4935449E33C56aB24b23fcd3246f13470;

    address public constant CURRENT_ACL_SUPERADMIN =
        0x4365F8e70CF38C6cA67DE41448508F2da8825500;

    address public constant MIMATIC =
        0x3B55E45fD6bd7d4724F5c47E0d1bCaEdd059263e;

    address public constant MIMATIC_WHALE =
        0xbE56bFF41AD57971DEDfBa69f88b1d085E349d47;

    address public constant DAIe = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;

    address public constant DAI_WHALE =
        0xED2a7edd7413021d440b09D654f3b87712abAB66;

    address public constant RATE_STRATEGY =
        0xf4a0039F2d4a2EaD5216AbB6Ae4C4C3AA2dB9b82;

    function setUp() public {}

    function testListing() public {
        ReserveConfig[] memory allConfigsBefore = AaveV3Helpers
            ._getReservesConfigs(false);

        vm.startPrank(GUARDIAN_AVALANCHE);

        AaveV3AvaMIMATICListingSteward listingSteward = new AaveV3AvaMIMATICListingSteward();

        IACLManager aclManager = AaveV3Avalanche.ACL_MANAGER;

        aclManager.addAssetListingAdmin(address(listingSteward));
        aclManager.addRiskAdmin(address(listingSteward));

        listingSteward.listAssetAddingOracle();

        vm.stopPrank();

        ReserveConfig[] memory allConfigsAfter = AaveV3Helpers
            ._getReservesConfigs(false);

        ReserveConfig memory expectedAssetConfig = ReserveConfig({
            symbol: 'miMatic',
            underlying: MIMATIC,
            aToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals: 18,
            ltv: 0,
            liquidationThreshold: 0,
            liquidationBonus: 0,
            liquidationProtocolFee: 1000,
            reserveFactor: 1000,
            usageAsCollateralEnabled: false,
            borrowingEnabled: true,
            interestRateStrategy: AaveV3Helpers
                ._findReserveConfig(allConfigsAfter, 'USDt', false)
                .interestRateStrategy,
            stableBorrowRateEnabled: false,
            isActive: true,
            isFrozen: false,
            isSiloed: false,
            supplyCap: 10_000_000,
            borrowCap: 0,
            debtCeiling: 0,
            eModeCategory: 1
        });

        AaveV3Helpers._validateReserveConfig(
            expectedAssetConfig,
            allConfigsAfter
        );

        AaveV3Helpers._noReservesConfigsChangesApartNewListings(
            allConfigsBefore,
            allConfigsAfter
        );

        AaveV3Helpers._validateReserveTokensImpls(
            vm,
            AaveV3Helpers._findReserveConfig(allConfigsAfter, 'miMatic', false),
            ReserveTokens({
                aToken: listingSteward.ATOKEN_IMPL(),
                stableDebtToken: listingSteward.SDTOKEN_IMPL(),
                variableDebtToken: listingSteward.VDTOKEN_IMPL()
            })
        );

        AaveV3Helpers._validateAssetSourceOnOracle(
            MIMATIC,
            listingSteward.PRICE_FEED()
        );

        // impl should be same as USDC
        AaveV3Helpers._validateReserveTokensImpls(
            vm,
            AaveV3Helpers._findReserveConfig(allConfigsAfter, 'USDC', false),
            ReserveTokens({
                aToken: listingSteward.ATOKEN_IMPL(),
                stableDebtToken: listingSteward.SDTOKEN_IMPL(),
                variableDebtToken: listingSteward.VDTOKEN_IMPL()
            })
        );

        _validatePoolActionsPostListing(allConfigsAfter);

        require(
            listingSteward.owner() == address(0),
            'INVALID_OWNER_POST_LISTING'
        );
    }

    function _validatePoolActionsPostListing(
        ReserveConfig[] memory allReservesConfigs
    ) internal {
        address aMIMATIC = AaveV3Helpers
            ._findReserveConfig(allReservesConfigs, 'miMatic', false)
            .aToken;
        address vMIMATIC = AaveV3Helpers
            ._findReserveConfig(allReservesConfigs, 'miMatic', false)
            .variableDebtToken;
        address sMIMATIC = AaveV3Helpers
            ._findReserveConfig(allReservesConfigs, 'miMatic', false)
            .stableDebtToken;
        address aDAI = AaveV3Helpers
            ._findReserveConfig(allReservesConfigs, 'DAI.e', false)
            .aToken;

        AaveV3Helpers._deposit(
            vm,
            MIMATIC_WHALE,
            MIMATIC_WHALE,
            MIMATIC,
            666 ether,
            true,
            aMIMATIC
        );

        // We check revert when trying to borrow (not enabled as collateral, so any mode works)
        try
            AaveV3Helpers._borrow(
                vm,
                MIMATIC_WHALE,
                MIMATIC_WHALE,
                MIMATIC,
                10 ether,
                1,
                sMIMATIC
            )
        {
            revert('_testProposal() : BORROW_NOT_REVERTING');
        } catch Error(string memory revertReason) {
            require(
                keccak256(bytes(revertReason)) == keccak256(bytes('34')),
                '_testProposal() : INVALID_VARIABLE_REVERT_MSG'
            );
            vm.stopPrank();
        }

        vm.startPrank(DAI_WHALE);
        IERC20(DAIe).transfer(MIMATIC_WHALE, 666 ether);
        vm.stopPrank();

        AaveV3Helpers._deposit(
            vm,
            MIMATIC_WHALE,
            MIMATIC_WHALE,
            DAIe,
            666 ether,
            true,
            aDAI
        );

        AaveV3Helpers._borrow(
            vm,
            MIMATIC_WHALE,
            MIMATIC_WHALE,
            MIMATIC,
            222 ether,
            2,
            vMIMATIC
        );

        // Not possible to borrow and repay when vdebt index doesn't changing, so moving 1s
        skip(1);

        AaveV3Helpers._repay(
            vm,
            MIMATIC_WHALE,
            MIMATIC_WHALE,
            MIMATIC,
            IERC20(MIMATIC).balanceOf(MIMATIC_WHALE),
            2,
            vMIMATIC,
            true
        );

        AaveV3Helpers._withdraw(
            vm,
            MIMATIC_WHALE,
            MIMATIC_WHALE,
            MIMATIC,
            type(uint256).max,
            aMIMATIC
        );
    }
}
