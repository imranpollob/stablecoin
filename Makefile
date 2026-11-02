.DEFAULT_GOAL := help

.PHONY: help all install build test poc invariant check fmt coverage sizes clean anvil deploy-local

help:
	@echo "make install       Initialize pinned Git submodules"
	@echo "make check         Check formatting, build, and run all tests"
	@echo "make poc           Run security regression tests"
	@echo "make invariant     Run the longer CI invariant profile"
	@echo "make coverage      Print coverage summary"
	@echo "make deploy-local  Broadcast to a local Anvil node"

all: check

install:
	git submodule update --init --recursive

build:
	forge build

test:
	forge test

poc:
	forge test --match-path 'test/poc/*.t.sol' -vv

invariant:
	FOUNDRY_PROFILE=ci forge test --match-path 'test/fuzz/**/*.t.sol'

check:
	forge fmt --check
	forge build --sizes
	forge test

fmt:
	forge fmt

coverage:
	forge coverage --report summary

sizes:
	forge build --sizes

clean:
	forge clean

anvil:
	anvil

deploy-local:
	forge script script/DeployDSC.s.sol:DeployDSC --rpc-url http://127.0.0.1:8545 --broadcast
