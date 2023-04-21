OUTPUT := harness/liquid-staking/GiantPoolBase.sol

all: $(OUTPUT)

# Multi line search replace:
# perl -0pe 's/\n    function beforeTokenTransfer(.+)\n[\s\S]+?\n    \}/\n    function beforeTokenTransfer\1\n    \}/g' \

harness/liquid-staking/GiantPoolBase.sol: ../contracts/liquid-staking/GiantPoolBase.sol
	sed 's/ from "\.\(.*\)";$$/ from "\.\.\/\.\.\/\.\.\/contracts\/liquid-staking\/\.\1";/' $^ \
		| sed 's/ from ".*\/EnumerableSet\.sol"/ from "..\/EnumerableSet\.sol"/' \
		| sed 's/bytes calldata/bytes32/' \
		| sed 's/bytes memory/bytes32/' \
		| sed 's/bytes storage/bytes32/' \
		| sed 's/bytes /bytes32 /' \
		| sed 's/bytes[)]/bytes32)/' \
		| sed 's/allocatedBlsPubKeyForWithdrawalBatch\[\(.\+\)\]\.length/allocatedBlsPubKeyForWithdrawalBatch[\1]/' \
		> $@

clean:
	rm -f $(OUTPUT)
