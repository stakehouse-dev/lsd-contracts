pragma solidity ^0.8.13;

import { GiantPoolBase } from "./GiantPoolBase.sol";
import { EnumerableSet } from "../EnumerableSet.sol";

contract GiantPoolBaseHarness is GiantPoolBase {
    using EnumerableSet for EnumerableSet.UintSet;

    function onStakeHarness(bytes32 _blsPublicKey) external {
        require(_blsPublicKey != 0);
        _onStake(_blsPublicKey);
    }

    function thisAddress() external view returns (address) {
      return address(this);
    }

    function ethBalanceOf(address _a) external view returns (uint256) {
      return _a.balance;
    }

    function beforeTokenTransfer(address _from, address _to, uint256 _amount) external {
    }

    function _isAssociatedDepositBatchesBoundedSetForIndex(EnumerableSet.UintSet storage _batches, uint256 _i) internal view returns (bool) {
        uint256 batchIndex = _batches.at(_i);
        // If the batchIndex is larger than depositBatchCount, it is an invariant violation.
        // Return false if that is the case:
        if (batchIndex > depositBatchCount) {
            return false;
        }
        uint256 batchCount;
        uint256 j;
        if (j < _batches.length()) {
            if (_batches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < _batches.length()) {
            if (_batches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < _batches.length()) {
            if (_batches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        for (; j < _batches.length(); ++j) {
            if (_batches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        // If there are multiple of the same element in the set, it is an internal invariant
        // violation of the set. If so, return false:
        if (batchCount != 1) {
            return false;
        }
        return true;
    }

    function isAssociatedDepositBatchesBoundedSet(address _user) external view returns (bool) {
        EnumerableSet.UintSet storage batches = setOfAssociatedDepositBatches[_user];
        uint256 i;
        if (i < batches.length()) {
            if (!_isAssociatedDepositBatchesBoundedSetForIndex(batches, i)) {
                return false;
            }
        }
        ++i;
        if (i < batches.length()) {
            if (!_isAssociatedDepositBatchesBoundedSetForIndex(batches, i)) {
                return false;
            }
        }
        ++i;
        if (i < batches.length()) {
            if (!_isAssociatedDepositBatchesBoundedSetForIndex(batches, i)) {
                return false;
            }
        }
        ++i;
        for (; i < batches.length(); ++i) {
            if (!_isAssociatedDepositBatchesBoundedSetForIndex(batches, i)) {
                return false;
            }
        }
        return true;
    }

    function _isRecycledDepositBatchesBoundedSetForIndex(uint256 _i) internal view returns (bool) {
        uint256 batchIndex = setOfRecycledDepositBatches.at(_i);
        // If the batchIndex is not smaller than depositBatchCount, it is an invariant violation.
        // Return false if that is the case:
        if (batchIndex >= depositBatchCount) {
            return false;
        }
        uint256 batchCount;
        uint256 j;
        if (j < setOfRecycledDepositBatches.length()) {
            if (setOfRecycledDepositBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < setOfRecycledDepositBatches.length()) {
            if (setOfRecycledDepositBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < setOfRecycledDepositBatches.length()) {
            if (setOfRecycledDepositBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        for (; j < setOfRecycledDepositBatches.length(); ++j) {
            if (setOfRecycledDepositBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        // If there are multiple of the same element in the set, it is an internal invariant
        // violation of the set. If so, return false:
        if (batchCount != 1) {
            return false;
        }
        return true;
    }

    function isRecycledDepositBatchesBoundedSet() external view returns (bool) {
        uint256 i;
        if (i < setOfRecycledDepositBatches.length()) {
            if (!_isRecycledDepositBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        if (i < setOfRecycledDepositBatches.length()) {
            if (!_isRecycledDepositBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        if (i < setOfRecycledDepositBatches.length()) {
            if (!_isRecycledDepositBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        for (; i < setOfRecycledDepositBatches.length(); ++i) {
            if (!_isRecycledDepositBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        return true;
    }

    function _isRecycledStakedBatchesBoundedSetForIndex(uint256 _i) internal view returns (bool) {
        uint256 batchIndex = setOfRecycledStakedBatches.at(_i);
        // If the batchIndex is not smaller than stakedBatchCount, it is an invariant violation.
        // Return false if that is the case:
        if (batchIndex >= stakedBatchCount) {
            return false;
        }
        uint256 batchCount;
        uint256 j;
        if (j < setOfRecycledStakedBatches.length()) {
            if (setOfRecycledStakedBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < setOfRecycledStakedBatches.length()) {
            if (setOfRecycledStakedBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        if (j < setOfRecycledStakedBatches.length()) {
            if (setOfRecycledStakedBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        ++j;
        for (; j < setOfRecycledStakedBatches.length(); ++j) {
            if (setOfRecycledStakedBatches.at(j) == batchIndex) {
                ++batchCount;
            }
        }
        // If there are multiple of the same element in the set, it is an internal invariant
        // violation of the set. If so, return false:
        if (batchCount != 1) {
            return false;
        }
        return true;
    }

    function isRecycledStakedBatchesBoundedSet() external view returns (bool) {
        uint256 i;
        if (i < setOfRecycledStakedBatches.length()) {
            if (!_isRecycledStakedBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        if (i < setOfRecycledStakedBatches.length()) {
            if (!_isRecycledStakedBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        if (i < setOfRecycledStakedBatches.length()) {
            if (!_isRecycledStakedBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        ++i;
        for (; i < setOfRecycledStakedBatches.length(); ++i) {
            if (!_isRecycledStakedBatchesBoundedSetForIndex(i)) {
                return false;
            }
        }
        return true;
    }

    function isRecycledStakedBatch(uint256 _batchIndex) external view returns (bool) {
        return setOfRecycledStakedBatches.contains(_batchIndex);
    }

    function nextFullRecycledStakedBatch() external view returns (int256) {
        uint256 i;
        if (i < setOfRecycledStakedBatches.length()) {
            uint256 batch = setOfRecycledStakedBatches.at(i);
            if (ethRecycledFromBatch[batch] == 0) return int256(batch);
        }
        ++i;
        if (i < setOfRecycledStakedBatches.length()) {
            uint256 batch = setOfRecycledStakedBatches.at(i);
            if (ethRecycledFromBatch[batch] == 0) return int256(batch);
        }
        ++i;
        if (i < setOfRecycledStakedBatches.length()) {
            uint256 batch = setOfRecycledStakedBatches.at(i);
            if (ethRecycledFromBatch[batch] == 0) return int256(batch);
        }
        ++i;
        for (; i < setOfRecycledStakedBatches.length(); ++i) {
            uint256 batch = setOfRecycledStakedBatches.at(i);
            if (ethRecycledFromBatch[batch] == 0) return int256(batch);
        }
        return -1;
    }

    function isRecycledDepositBatch(uint256 _batchIndex) external view returns (bool) {
        return setOfRecycledDepositBatches.contains(_batchIndex);
    }

    function totalETHRecycled() external view returns (uint256) {
        uint256 sum;
        if (0 < setOfRecycledDepositBatches.length()) {
            sum += ethRecycledFromBatch[setOfRecycledDepositBatches.at(0)];
        }
        if (1 < setOfRecycledDepositBatches.length()) {
            sum += ethRecycledFromBatch[setOfRecycledDepositBatches.at(1)];
        }
        if (2 < setOfRecycledDepositBatches.length()) {
            sum += ethRecycledFromBatch[setOfRecycledDepositBatches.at(2)];
        }
        for (uint256 i = 3; i < setOfRecycledDepositBatches.length(); ++i) {
            sum += ethRecycledFromBatch[setOfRecycledDepositBatches.at(i)];
        }
        return sum;
    }

    function isBatchIndexAssociatedToBLSKey(uint256 _batchIndex) external view returns (bool) {
        return allocatedBlsPubKeyForWithdrawalBatch[_batchIndex] != 0;
    }

    function isAssociatedDepositBatch(address _user, uint256 _batchIndex) external view returns (bool) {
        return setOfAssociatedDepositBatches[_user].contains(_batchIndex);
    }

    function computeWithdrawableAmountOfETH(address _user) external view returns (uint256) {
        uint256 sum;
        uint256 i;
        if (i <= depositBatchCount) {
            if (!(i < stakedBatchCount && !setOfRecycledStakedBatches.contains(i))) {
                sum += totalETHFundedPerBatch[_user][i];
            }
        }
        ++i;
        if (i <= depositBatchCount) {
            if (!(i < stakedBatchCount && !setOfRecycledStakedBatches.contains(i))) {
                sum += totalETHFundedPerBatch[_user][i];
            }
        }
        ++i;
        if (i <= depositBatchCount) {
            if (!(i < stakedBatchCount && !setOfRecycledStakedBatches.contains(i))) {
                sum += totalETHFundedPerBatch[_user][i];
            }
        }
        ++i;
        for (; i <= depositBatchCount; ++i) {
            if (i < stakedBatchCount && !setOfRecycledStakedBatches.contains(i)) continue;
            sum += totalETHFundedPerBatch[_user][i];
        }
        return sum;
    }
}
