//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { PoolHelpers, CustomPoolConfig, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { ConstantSumFactory } from "../contracts/factories/ConstantSumFactory.sol";
import { ConstantProductFactory } from "../contracts/factories/ConstantProductFactory.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { NftCheckHook } from "../contracts/hooks/NftCheckHook.sol";
import { MockNft } from "../contracts/mocks/MockNft.sol";
import { Router } from "../contracts/mocks/Router.sol";
import { MockLinked } from "../contracts/mocks/MockLinked.sol";
import { MockStable } from "../contracts/mocks/MockStable.sol";

enum FactoryType {
    ConstantSum,
    ConstantProduct,
    Weighted
}

contract DeployNftHookHelper is PoolHelpers, ScaffoldHelpers {
    bool private constant ENABLE_DONATION = true;
    bool private constant DISABLE_UNBALANCED_LIQUIDITY = false;
    uint256 private constant SWAP_FEE_PERCENTAGE = 0.01e18;

    function deployNftHookHelper(address token, FactoryType factoryType) public {
        // Start creating the transactions
        // address deployerAddress = address(uint160(getDeployerAddress())); TODO
        uint256 deployerPrivateKey = getDeployerPrivateKey();
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a Sample Token - will throw warning on deploy as it is not used in the following code
        // however it is needed in order to interact with the contract via scaffold's patterns
        MockLinked sampleToken = new MockLinked("sampleToken", "sampleToken", 1);

        // Deploy an Nft and mint one
        MockNft mockNft = new MockNft("NFTFactory", "NFTF");
        console.log("MockNft: %s", address(mockNft));

        uint256 tokenId = mockNft.mintNft("https://0a050602b1c1aeae1063a0c8f5a7cdac.ipfscdn.io/ipfs/QmSiA82PQNuWuBfQtuzWKwnZV94qs34jrW1L6PaR69jeoE/metadata.json");

        // Deploy a hook
        address nftCheckHook = address(
            new NftCheckHook(vault, address(mockNft), tokenId, token, "RWA Token", "RWAT", 1000e18, 10e16)
        );
        console.log("NftCheckHook deployed at address: %s", nftCheckHook);

        // Set the pool's deployment, registration, and initialization config
        address linkedTokenAddress = NftCheckHook(nftCheckHook).getLinkedToken();
        console.log("linkedTokenAddress: %s", linkedTokenAddress);
        // TODO make sure the tokens are sorted correctly and match with pool weights
        CustomPoolConfig memory poolConfig = getPoolConfig(linkedTokenAddress, token, factoryType);
        InitializationConfig memory initConfig = getCheckSumPoolInitConfig(linkedTokenAddress, token);

        address pool;
        if (factoryType == FactoryType.ConstantSum) {
            // Deploy a factory
            ConstantSumFactory factory = new ConstantSumFactory(vault, 365 days); // pauseWindowDuration
            console.log("Constant Sum Factory deployed at: %s", address(factory));

            // Deploy a pool and register it with the vault
            pool = factory.create(
                poolConfig.name,
                poolConfig.symbol,
                poolConfig.salt,
                poolConfig.tokenConfigs,
                poolConfig.swapFeePercentage,
                poolConfig.protocolFeeExempt,
                poolConfig.roleAccounts,
                nftCheckHook, // poolHooksContract --> calls onRegister
                poolConfig.liquidityManagement
            );
            console.log("SumPoolWithNftCheckHook deployed at: %s", pool);
        } else if (factoryType == FactoryType.ConstantProduct) {
            // Deploy a factory
            ConstantProductFactory factory = new ConstantProductFactory(vault, 365 days); //pauseWindowDuration
            console.log("Constant Product Factory deployed at: %s", address(factory));

            // Deploy a pool and register it with the vault
            pool = factory.create(
                poolConfig.name,
                poolConfig.symbol,
                poolConfig.salt,
                poolConfig.tokenConfigs,
                poolConfig.swapFeePercentage,
                poolConfig.protocolFeeExempt,
                poolConfig.roleAccounts,
                nftCheckHook,
                poolConfig.liquidityManagement
            );
            console.log("ConstantProductPoolWithNftCheckHook deployed at: %s", pool);
        } else if (factoryType == FactoryType.Weighted) {
            // Deploy a  factory
            WeightedPoolFactory factory = new WeightedPoolFactory(vault, 365 days, "Factory v1", "Pool v1");
            console.log("Weighted Pool Factory deployed at: %s", address(factory));

            // Deploy a pool and register it with the vault
            /// @notice passing args directly to avoid stack too deep error
             pool = factory.create(
                "80/20 Weighted Pool", // string name
                "80-20-WP", // string symbol
                poolConfig.tokenConfigs, // getTokenConfigs(token1, token2), // TokenConfig[] tokenConfigs
                getNormailzedWeights(), // uint256[] normalizedWeights
                poolConfig.roleAccounts, // PoolRoleAccounts roleAccounts
                SWAP_FEE_PERCENTAGE, // uint256 swapFeePercentage (1%)
                nftCheckHook, // address poolHooksContract
                ENABLE_DONATION,
                DISABLE_UNBALANCED_LIQUIDITY,
                keccak256(abi.encode(block.number)) // bytes32 salt
            );
            console.log("Weighted Pool deployed at: %s", pool);
        }

        // Approve the router to spend tokens for pool initialization
        approveRouterWithPermit2(initConfig.tokens);

        // Approve the hook to transfer bpt tokens
        IERC20(pool).approve(nftCheckHook, type(uint256).max);

        address testUserAddress = address(uint160(getTestUserAddress()));
        MockStable(token).mint(100e18);
        MockStable(token).transfer(testUserAddress, 100e18);

        // deploy mock router so we can get the abi to call the initialize function
        Router router2 = new Router();

        vm.stopBroadcast();
    }

    /**
     * @dev Set all of the configurations for deploying and registering a pool here
     * @notice TokenConfig encapsulates the data required for the Vault to support a token of the given type.
     * For STANDARD tokens, the rate provider address must be 0, and paysYieldFees must be false.
     * All WITH_RATE tokens need a rate provider, and may or may not be yield-bearing.
     */
    function getPoolConfig(address token1, address token2, FactoryType factoryType ) internal view returns (CustomPoolConfig memory config) {
        // string memory name = "NFT " + factoryType + " Pool"; // name for the pool
        string memory name = factoryType == FactoryType.ConstantSum ? "NFT Costant Sum Pool" : factoryType == FactoryType.Weighted ? "NFT Weighted Pool" : "NFT Constant Product Pool"; // symbol for the BPT
        string memory symbol = factoryType == FactoryType.ConstantSum ? "NFTCSP" : factoryType == FactoryType.Weighted ? "NFTWTP" : "NFTCPP"; // symbol for the BPT
        bytes32 salt = keccak256(abi.encode(block.number)); // salt for the pool deployment via factory
        uint256 swapFeePercentage = SWAP_FEE_PERCENTAGE; // 1%
        bool protocolFeeExempt = true;
        address poolHooksContract = address(0); // zero address if no hooks contract is needed

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2); // An array of descriptors for the tokens the pool will manage.
        tokenConfigs[0] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token1),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });
        tokenConfigs[1] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token2),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });

        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: address(0), // Account empowered to pause/unpause the pool (or 0 to delegate to governance)
            swapFeeManager: address(0), // Account empowered to set static swap fees for a pool (or 0 to delegate to goverance)
            poolCreator: address(0) // Account empowered to set the pool creator fee percentage
        });
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: DISABLE_UNBALANCED_LIQUIDITY,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false,
            enableDonation: ENABLE_DONATION
        });

        config = CustomPoolConfig({
            name: name,
            symbol: symbol,
            salt: salt,
            tokenConfigs: sortTokenConfig(tokenConfigs),
            swapFeePercentage: swapFeePercentage,
            protocolFeeExempt: protocolFeeExempt,
            roleAccounts: roleAccounts,
            poolHooksContract: poolHooksContract,
            liquidityManagement: liquidityManagement
        });
    }

    /**
     * @dev Set the pool initialization configurations here
     * @notice this is where the amounts of tokens to be initially added to the pool are set
     */
    function getCheckSumPoolInitConfig(
        address token1,
        address token2
    ) internal pure returns (InitializationConfig memory config) {
        IERC20[] memory tokens = new IERC20[](2); // Array of tokens to be used in the pool
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        uint256[] memory exactAmountsIn = new uint256[](2); // Exact amounts of tokens to be added, sorted in token alphanumeric order
        exactAmountsIn[0] = 50e18; // amount of token1 to send during pool initialization
        exactAmountsIn[1] = 50e18; // amount of token2 to send during pool initialization
        uint256 minBptAmountOut = 99e18; // Minimum amount of pool tokens to be received
        bool wethIsEth = false; // If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
        bytes memory userData = bytes(""); // Additional (optional) data required for adding initial liquidity

        config = InitializationConfig({
            tokens: InputHelpers.sortTokens(tokens),
            exactAmountsIn: exactAmountsIn,
            minBptAmountOut: minBptAmountOut,
            wethIsEth: wethIsEth,
            userData: userData
        });
    }

    /// @dev Set the weights for each token in the pool
    function getNormailzedWeights() internal pure returns (uint256[] memory normalizedWeights) {
        normalizedWeights = new uint256[](2);
        normalizedWeights[0] = uint256(80e16);
        normalizedWeights[1] = uint256(20e16);
    }
}

