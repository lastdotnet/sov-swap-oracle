// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/TwapOracle.sol";

contract MockSovereignPool {
    address[] public tokens;

    constructor(address token0, address token1) {
        tokens.push(token0);
        tokens.push(token1);
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }
}

contract TwapOracleTest is Test {
    TwapOracle oracle;
    MockSovereignPool mockPool;
    address token0 = address(0x123);
    address token1 = address(0x456);

    function setUp() public {
        // Initialize the mock pool and oracle
        mockPool = new MockSovereignPool(token0, token1);
        oracle = new TwapOracle(address(mockPool), uint256(2));
    }

    function testInitialization() public {
        // Check initial values
        (uint256 timestampZeroToOne, uint256 cumulativePriceZeroToOne) = oracle.zeroToOneObservations(oracle.zeroToOneIndex());
        (uint256 timestampOneToZero, uint256 cumulativePriceOneToZero) = oracle.oneToZeroObservations(oracle.oneToZeroIndex());

        assertEq(timestampZeroToOne, block.timestamp);
        assertEq(timestampOneToZero, block.timestamp);
        assertEq(cumulativePriceZeroToOne, 0);
        assertEq(cumulativePriceOneToZero, 0);
        assertEq(oracle.cumulativeVolumeZeroToOne(), 0);
        assertEq(oracle.cumulativeVolumeOneToZero(), 0);
    }

    function testWriteOracleUpdateZeroToOne() public {
        // Simulate a token0 -> token1 swap
        uint256 amountIn = 100e18;
        uint256 fee = 0.01e18; // 1%
        uint256 amountOut = 200e18;

        // Advance time by 1 hour
        skip(3600);

        // Call writeOracleUpdate for token0 -> token1
        oracle.writeOracleUpdate(true, amountIn, fee, amountOut);

        // Verify the updated cumulative price and timestamp
        (uint256 timestamp, uint256 cumulativePrice) = oracle.zeroToOneObservations(oracle.zeroToOneIndex());
        assertEq(timestamp, block.timestamp);
        assertTrue(cumulativePrice > 0);
        assertEq(oracle.cumulativeVolumeZeroToOne(), amountIn);
    }

    function testWriteOracleUpdateOneToZero() public {
        // Simulate a token1 -> token0 swap
        uint256 amountIn = 150e18;
        uint256 fee = 0.02e18; // 2%
        uint256 amountOut = 75e18;

        // Advance time by 1 hour
        skip(3600);

        // Call writeOracleUpdate for token1 -> token0
        oracle.writeOracleUpdate(false, amountIn, fee, amountOut);

        // Verify the updated cumulative price and timestamp
        (uint256 timestamp, uint256 cumulativePrice) = oracle.oneToZeroObservations(oracle.oneToZeroIndex());
        assertEq(timestamp, block.timestamp);
        assertTrue(cumulativePrice > 0);
        assertEq(oracle.cumulativeVolumeOneToZero(), amountIn);
    }

    function testConsultZeroToOneTWAP() public {
        // Simulate token0 -> token1 swaps over time
        oracle.writeOracleUpdate(true, 100e18, 0.01e18, 200e18);
        skip(3600); // 1 hour
        oracle.writeOracleUpdate(true, 200e18, 0.01e18, 400e18);
        skip(3600); // Another hour

        uint256 window = 7200; // 2 hours
        uint256 twap = oracle.consult(token0, window);

        // Validate the TWAP is within expected range
        assertTrue(twap > 0);
    }

    function testConsultOneToZeroTWAP() public {
        // Simulate token1 -> token0 swaps over time
        oracle.writeOracleUpdate(false, 150e18, 0.02e18, 75e18);
        skip(3600); // 1 hour
        oracle.writeOracleUpdate(false, 300e18, 0.02e18, 150e18);
        skip(3600); // Another hour

        uint256 window = 7200; // 2 hours
        uint256 twap = oracle.consult(token1, window);

        // Validate the TWAP is within expected range
        assertTrue(twap > 0);
    }

    function testInsufficientDataForToken0() public {
        // Attempt to consult TWAP without sufficient data
        uint256 window = 3600;
        vm.expectRevert(TwapOracle.InsufficientDataForToken0.selector);
        oracle.consult(token0, window);
    }

    function testInsufficientDataForToken1() public {
        // Attempt to consult TWAP without sufficient data
        uint256 window = 3600;
        vm.expectRevert(TwapOracle.InsufficientDataForToken1.selector);
        oracle.consult(token1, window);
    }

    function testMultipleSwapsOneToZeroOutInsideMinTimeElapsed() public {
        // Simulate token1 -> token0 swaps over time
        oracle.writeOracleUpdate(false, 150e18, 0.02e18, 75e18);
        skip(3600); // 1 hour
        oracle.writeOracleUpdate(false, 300e18, 0.02e18, 150e18);
        uint256 window = 3600; // 2 hours
        uint256 twap = oracle.consult(token1, window);
        oracle.writeOracleUpdate(false, 300e18, 0.02e18, 150e18);
        assertEq(twap, oracle.consult(token1, window));
    }

    function testMultipleSwapsZeroToOneOutInsideMinTimeElapsed() public {
        // Simulate token1 -> token0 swaps over time
        oracle.writeOracleUpdate(true, 150e18, 0.02e18, 75e18);
        skip(3600); // 1 hour
        oracle.writeOracleUpdate(true, 300e18, 0.02e18, 150e18);
        uint256 window = 3600; // 2 hours
        uint256 twap = oracle.consult(token1, window);
        oracle.writeOracleUpdate(true, 300e18, 0.02e18, 150e18);
        assertEq(twap, oracle.consult(token1, window));
    }

    function testPoolGetter() public {
        assertEq(oracle.pool(), address(mockPool));
    }

    function testInvalidToken() public {
        vm.expectRevert(TwapOracle.InvalidToken.selector);
        oracle.consult(address(0x789), 3600);
    }
}
