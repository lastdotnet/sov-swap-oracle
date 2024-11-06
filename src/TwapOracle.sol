pragma solidity ^0.8.28;

import {ISovereignOracle} from "valantis-core/oracles/interfaces/ISovereignOracle.sol";
import {ISovereignPool} from "valantis-core/pools/interfaces/ISovereignPool.sol";

contract TwapOracle is ISovereignOracle {
    struct Observation {
        uint256 timestamp;
        uint256 cumulativePrice;
    }

    Observation[10] public zeroToOneObservations; // Circular buffer for token0 -> token1
    Observation[10] public oneToZeroObservations; // Circular buffer for token1 -> token0

    uint8 public zeroToOneIndex;
    uint8 public oneToZeroIndex;

    uint256 public cumulativeVolumeZeroToOne; // Volume for token0 -> token1 swaps
    uint256 public cumulativeVolumeOneToZero; // Volume for token1 -> token0 swaps
    uint256 public minTimeElapsed;

    address private _token0;
    address private _token1;
    address private _pool;

    error InsufficientDataForToken0();
    error InsufficientDataForToken1();
    error InvalidToken();

    constructor(address pool_, uint256 minTimeElapsed_) {
        address[] memory tokens = ISovereignPool(pool_).getTokens();
        _pool = pool_;
        _token0 = tokens[0];
        _token1 = tokens[1];
        uint256 currentTimestamp = block.timestamp;
        minTimeElapsed = minTimeElapsed_;
        zeroToOneObservations[zeroToOneIndex] = Observation(currentTimestamp, 0);
        oneToZeroObservations[oneToZeroIndex] = Observation(currentTimestamp, 0);
    }

    function pool() external view override returns (address) {
        return _pool;
    }

    function writeOracleUpdate(
        bool isZeroToOne,
        uint256 amountInMinusFee,
        uint256 fee,
        uint256 amountOut
    ) external {
        uint256 currentTimestamp = block.timestamp;
        uint256 price = (amountOut * 1e18) / amountInMinusFee;
        uint256 adjustedPrice = price * (1e18 - fee) / 1e18;

        uint256 timeElapsed;
        if (isZeroToOne) {
            timeElapsed = currentTimestamp - zeroToOneObservations[zeroToOneIndex].timestamp;
            if (timeElapsed < minTimeElapsed) {
                return;
            }
            zeroToOneObservations[zeroToOneIndex].cumulativePrice += adjustedPrice * timeElapsed;
            cumulativeVolumeZeroToOne += amountInMinusFee;

            // Move to the next index in the circular buffer
            zeroToOneIndex = uint8((zeroToOneIndex + 1) % zeroToOneObservations.length);
            zeroToOneObservations[zeroToOneIndex] = Observation(
                currentTimestamp,
                zeroToOneIndex == 0
                    ? zeroToOneObservations[zeroToOneObservations.length - 1].cumulativePrice
                    : zeroToOneObservations[zeroToOneIndex - 1].cumulativePrice
            );
        } else {
            timeElapsed = currentTimestamp - oneToZeroObservations[oneToZeroIndex].timestamp;
            if (timeElapsed < minTimeElapsed) {
                return;
            }
            oneToZeroObservations[oneToZeroIndex].cumulativePrice += adjustedPrice * timeElapsed;
            cumulativeVolumeOneToZero += amountInMinusFee;

            // Move to the next index in the circular buffer
            oneToZeroIndex = uint8((oneToZeroIndex + 1) % oneToZeroObservations.length);
            oneToZeroObservations[oneToZeroIndex] = Observation(
                currentTimestamp,
                oneToZeroIndex == 0
                    ? oneToZeroObservations[oneToZeroObservations.length - 1].cumulativePrice
                    : oneToZeroObservations[oneToZeroIndex - 1].cumulativePrice
            );
        }
    }


    function consult(address token, uint256 window) external view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        uint256 timeElapsed;

        if (token == _token0) {
            Observation memory oldestObservation = zeroToOneObservations[(zeroToOneIndex + 1) % zeroToOneObservations.length];
            timeElapsed = currentTimestamp - oldestObservation.timestamp;
            if (timeElapsed < window) {
                revert InsufficientDataForToken0();
            }

            // Calculate TWAP using cumulative data within the window
            uint256 cumulativePriceAtWindow = zeroToOneObservations[zeroToOneIndex].cumulativePrice - oldestObservation.cumulativePrice;
            return cumulativePriceAtWindow / window;

        } else if (token == _token1) {
            Observation memory oldestObservation = oneToZeroObservations[(oneToZeroIndex + 1) % oneToZeroObservations.length];
            timeElapsed = currentTimestamp - oldestObservation.timestamp;
            if (timeElapsed < window) {
                revert InsufficientDataForToken1();
            }

            // Calculate TWAP using cumulative data within the window
            uint256 cumulativePriceAtWindow = oneToZeroObservations[oneToZeroIndex].cumulativePrice - oldestObservation.cumulativePrice;
            return cumulativePriceAtWindow / window;
        } else {
            revert InvalidToken();
        }
    }
}
