// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { MockNft } from "../contracts/mocks/MockNft.sol";
import { MockLinked } from "../contracts/mocks/MockLinked.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { NftCheckHook } from "../contracts/hooks/NftCheckHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import {
    TokenType,
    HooksConfig,
    LiquidityManagement,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";


contract HelperForTests is BaseVaultTest{
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal linkedTokenIdx;
    uint256 internal usdcIdx;

    address payable internal hookOwner;
    uint256 internal hookOwnerKey;
    address payable internal randomUser;
    uint256 internal randomUserKey;

    MockNft mockNft;
    uint256 tokenId;
    address nftCheckHook;
    bool nftIsDeposited;
    MockLinked linkedToken;
    bool linkedTokenIsMinted;
    address linkedTokenAddress;

    uint256 constant OWNER_LINKED_TOKEN_INITIAL_BALANCE = 1e3*1e18;
    uint256 constant OWNER_USDC_INITIAL_BALANCE = 1e3*1e18;
    uint256 constant RANDOM_USER_USDC_INITIAL_BALANCE = 100*1e18;
    uint256 constant POOL_INITIAL_AMOUNT = 50e18;
    uint256 constant SWAP_FEE_PERCENTAGE = 0.01e18;  // 1%
    // random user swap amount in
    uint256 constant USDC_SWAP_AMOUNT_IN = 10e18;
    uint256 constant EXPECTED_LINKED_TOKEN_AMOUNT_OUT = 8249999999999999999; // for CP
    uint256 constant SETTLEMENT_FEE = 10e16;


    modifier transferNFT_approveBPT_initializePool() {
        // Transfer NFT, approve bpt transfer to hook and initialize pool
        vm.startPrank(hookOwner);
        mockNft.transferFrom(hookOwner, nftCheckHook, 0);
        BalancerPoolToken(pool).approve(nftCheckHook, type(uint256).max);
        initPool();
        vm.stopPrank();
        // Owner has no BPT
        assertEq(BalancerPoolToken(pool).balanceOf(hookOwner), 0, "hookOwner has BPT");
        _;
    }

    function _setUp() public {
        address hookOwnerP;
        (hookOwnerP, hookOwnerKey) = makeAddrAndKey("hookOwner");
        hookOwner = payable(hookOwnerP);
        address randomUserP;
        (randomUserP, randomUserKey) = makeAddrAndKey("randomUser");
        randomUser = payable(randomUserP);

        mintNft();

        super.setUp();
        poolInitAmount = POOL_INITIAL_AMOUNT; // overriding
        poolHooksContract = nftCheckHook; // overriding
        usdc.mint(hookOwner, OWNER_USDC_INITIAL_BALANCE);
        usdc.mint(randomUser, RANDOM_USER_USDC_INITIAL_BALANCE);

        linkedTokenAddress = NftCheckHook(nftCheckHook).getLinkedToken(); // get linked token address
        linkedToken = MockLinked(linkedTokenAddress); // linked token
        tokens.push(ERC20TestToken(linkedTokenAddress)); // push linked token to tokens as ERC20TestToken
        linkedTokenIsMinted = true; // to enable the pool creation
        (linkedTokenIdx, usdcIdx) = getSortedIndexes(address(linkedToken), address(usdc));

        pool = createPool();
        vaultConvertFactor = vault.getConvertFactor();

        // Grants hookOwner the ability to change the static swap fee percentage.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), hookOwner);
    }

    function _testInitialBalances() public {
        /// Owner
        // Owner has an NFT
        assertEq(mockNft.balanceOf(hookOwner) > 0, true, "hookOwner does not have an NFT");
        // Hook expects the mockNft NFT
        assertEq(address(mockNft), NftCheckHook(nftCheckHook).getNftContract());
        // Owner balances
        uint256 hookOwnerLinkedBalance = linkedToken.balanceOf(hookOwner);
        assertEq(hookOwnerLinkedBalance, OWNER_LINKED_TOKEN_INITIAL_BALANCE, "hookOwner wrong liniked tokens balance");
        uint256 hookOwnerUsdcBalance = usdc.balanceOf(hookOwner);
        assertEq(hookOwnerUsdcBalance, OWNER_USDC_INITIAL_BALANCE, "hookOwner wrong usdc tokens balance");
        // Owner has no BPT
        assertEq(BalancerPoolToken(pool).balanceOf(hookOwner), 0);

        /// RandomUser
        uint256 randomUserLinkedBalance = linkedToken.balanceOf(randomUser);
        assertEq(randomUserLinkedBalance, 0, "RandomUser has some linked tokens");
        uint256 randomUserUsdcBalance = usdc.balanceOf(randomUser);
        assertEq(randomUserUsdcBalance, RANDOM_USER_USDC_INITIAL_BALANCE, "RandomUser wrong usdc tokens balance");
    }

    function _swap(address user, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, bool reverts) internal {
        vm.startPrank(user);
        // permissions
        usdc.approve(address(permit2), type(uint256 ).max);
        linkedToken.approve(address(permit2), type(uint256 ).max);
        permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(linkedToken), address(router), type(uint160).max, type(uint48).max);
        // expect revert?
        if (reverts) {
            vm.expectRevert();
        }
        RouterMock(router).swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function _firstUserSwaps(uint256 _swapFeePercentage) internal virtual returns (uint256 expectedLinkedTokenOut) {}

    function _testOwnerCanRemoveLiquidityAfterSettlement(uint256 expectedBptAmountOut) internal {
        _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(SWAP_FEE_PERCENTAGE);

        uint256 bptAmount = IERC20(pool).balanceOf(hookOwner);
        // for some reason the bpt amount is a lot different than 2*POOL_INITIAL_AMOUNT, TODO
        assertEq(bptAmount, expectedBptAmountOut, "Wrong bpt amount");
        _ownerRemovesLiquidityProportional(bptAmount, false);
    }

    function _testRugPulling() internal {
        // random user swaps usdc for linked token
        uint256 expectedLinkedTokenOut = _firstUserSwaps(SWAP_FEE_PERCENTAGE);

        // Owner removes liquidity but has no bpt
        uint256 bptAmount = IERC20(pool).balanceOf(hookOwner);
        assertEq(bptAmount, 0, "Wrong bpt amount");
        // true means it reverts
        _ownerRemovesLiquidityProportional(POOL_INITIAL_AMOUNT/10, true);
    }

    function _ownerSettlesPool() internal {
        // hook owner settles pool
        vm.startPrank(hookOwner);
        usdc.approve(nftCheckHook, type(uint256).max);
        NftCheckHook(nftCheckHook).settle();
        vm.stopPrank();
    }

    function _userRedeems() internal virtual {
        // random user redeems
        vm.startPrank(randomUser);
        linkedToken.approve(nftCheckHook, type(uint256).max);
        NftCheckHook(nftCheckHook).redeem();
        vm.stopPrank();
    }

    function _userRedeemsAfterFirstSwapAndOwnerSettlement(uint256 expectedLinkedTokenOut) internal virtual {}

    function _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(uint256 _swapFeePercentage) internal {
        // random user swaps usdc for linked token
        uint256 expectedLinkedTokenOut = _firstUserSwaps(_swapFeePercentage);

        // Owner settles pool
        _ownerSettlesPool();

        // random user redeems
        _userRedeemsAfterFirstSwapAndOwnerSettlement(expectedLinkedTokenOut);

        // random user swap reverts because pool is settled
        _swap(randomUser, usdc, IERC20(linkedTokenAddress), USDC_SWAP_AMOUNT_IN, true);
    }

    /// HELPERS ///

    function _ownerRemovesLiquidityProportional(uint256 amountOut, bool reverts) internal {
        vm.startPrank(hookOwner);
        IERC20(pool).approve(address(router), type(uint256).max);
        
        if (reverts) vm.expectRevert();
        router.removeLiquidityProportional(pool, amountOut, [uint256(0),uint256(0)].toMemoryArray(), false, bytes(""));
        vm.stopPrank();
    }

    function _ownerAddsLiquidity(uint256[] memory exactAmountsIn) internal {
        vm.prank(hookOwner);
        router.addLiquidityUnbalanced(
            pool,
            exactAmountsIn,
            0,
            false,
            bytes("")
        );
    }

    function mintNft() internal {
        vm.prank(hookOwner);
        mockNft = new MockNft("NFTFactory", "NFTF");
        vm.prank(hookOwner);
        tokenId = mockNft.mintNft("https://0a050602b1c1aeae1063a0c8f5a7cdac.ipfscdn.io/ipfs/QmSiA82PQNuWuBfQtuzWKwnZV94qs34jrW1L6PaR69jeoE/metadata.json");
    }

    function createHook() internal override returns (address) {
        // hookOwner will be the owner of the hook
        vm.prank(hookOwner);
        nftCheckHook = address(
            new NftCheckHook(
                vault,
                address(mockNft),
                tokenId,
                address(usdc),
                "RWA Token",
                "RWAT",
                OWNER_LINKED_TOKEN_INITIAL_BALANCE,
                SETTLEMENT_FEE
            )
        );
        vm.label(nftCheckHook, "Nft Check Hook");
        return nftCheckHook;
    }

    function createPool() internal override returns (address) {
        if (!linkedTokenIsMinted) return address(0);
        return _createPool([address(linkedToken), address(usdc)].toMemoryArray(), "pool");
    }

    function initPool() internal override {
        if (mockNft.ownerOf(tokenId) == nftCheckHook) {
            vm.startPrank(hookOwner);
            usdc.approve(address(permit2), type(uint256 ).max);
            linkedToken.approve(address(permit2), type(uint256 ).max);
            permit2.approve(address(linkedToken), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
            _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
            vm.stopPrank();
        }
    }

    function _initPool(
        address poolToInit,
        uint256[] memory amountsIn,
        uint256 minBptOut
    ) internal override returns (uint256 bptOut) {
        
        IERC20[] memory tokens =  new IERC20[](2);
        if (address(linkedToken) > address(usdc)) {
            tokens[0] = IERC20(address(usdc));
            tokens[1] = IERC20(linkedTokenAddress);

        } else {
            tokens[1] = IERC20(address(usdc));
            tokens[0] = IERC20(linkedTokenAddress);
        }

        return router.initialize(poolToInit, tokens, amountsIn, minBptOut, false, bytes(""));
    }




    struct CustomPoolConfig {
        string name;
        string symbol;
        bytes32 salt;
        TokenConfig[] tokenConfigs;
        uint256 swapFeePercentage;
        bool protocolFeeExempt;
        PoolRoleAccounts roleAccounts;
        address poolHooksContract;
        LiquidityManagement liquidityManagement;
    }

    /**
     * Sorts the tokenConfig array into alphanumeric order
     */
    function sortTokenConfig(TokenConfig[] memory tokenConfig) internal pure returns (TokenConfig[] memory) {
        for (uint256 i = 0; i < tokenConfig.length - 1; i++) {
            for (uint256 j = 0; j < tokenConfig.length - i - 1; j++) {
                if (tokenConfig[j].token > tokenConfig[j + 1].token) {
                    // Swap if they're out of order.
                    (tokenConfig[j], tokenConfig[j + 1]) = (tokenConfig[j + 1], tokenConfig[j]);
                }
            }
        }
        return tokenConfig;
    }

    function getProductPoolConfig(
        address token1,
        address token2
    ) internal view returns (CustomPoolConfig memory config) {
        string memory name = "Constant Product Pool"; // name for the pool
        string memory symbol = "CPP"; // symbol for the BPT
        bytes32 salt = keccak256(abi.encode(block.number)); // salt for the pool deployment via factory
        uint256 swapFeePercentage = SWAP_FEE_PERCENTAGE; // 1%
        bool protocolFeeExempt = false;
        address poolHooksContract = address(0); // zero address if no hooks contract is needed

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2); // An array of descriptors for the tokens the pool will manage
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
            disableUnbalancedLiquidity: false,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false,
            enableDonation: true
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
}