import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Address, Abi } from 'viem';
import type { ContractCallData } from '@vfat-io/sickle-sdk';

// Mock sickle-sdk before importing wrapper
vi.mock('@vfat-io/sickle-sdk', () => {
  const makeMockCall = (functionName: string) => {
    return vi.fn().mockImplementation(async (params: Record<string, unknown>) => ({
      chainId: params.chainId ?? 8453,
      functionName,
      args: [`arg0_${functionName}`, `arg1_${functionName}`, `arg2_${functionName}`],
      abi: [{ type: 'function', name: functionName }] as unknown as Abi,
      address: params.walletAddress ?? '0xStrategyAddress',
      value: 0n,
      gas: BigInt(100000),
    }));
  };

  return {
    sickle: {
      lp: {
        deposit: makeMockCall('deposit'),
        depositToken: makeMockCall('deposit'),
        depositUnderlying: makeMockCall('deposit'),
        increase: {
          withToken: makeMockCall('increase'),
          withUnderlying: makeMockCall('increase'),
        },
        harvest: makeMockCall('harvest'),
        withdraw: {
          toLp: makeMockCall('simpleWithdraw'),
          toToken: makeMockCall('withdraw'),
          toUnderlying: makeMockCall('withdraw'),
        },
        compound: makeMockCall('compound'),
      },
      nft: {
        deposit: makeMockCall('deposit'),
        depositToken: makeMockCall('deposit'),
        depositUnderlying: makeMockCall('deposit'),
        increase: {
          withToken: makeMockCall('increase'),
          withUnderlying: makeMockCall('increase'),
        },
        harvest: makeMockCall('harvest'),
        decrease: {
          toToken: makeMockCall('decrease'),
          toUnderlying: makeMockCall('decrease'),
        },
        withdraw: makeMockCall('simpleWithdraw'),
        rebalance: makeMockCall('rebalance'),
      },
    },
  };
});

import { createWrapperSickle } from '../src/wrapper';
import { sickle } from '@vfat-io/sickle-sdk';
import sickleWrapperAbi from '../src/abis/SickleWrapper';
import wrapperFactoryAbi from '../src/abis/WrapperFactory';

const FACTORY_ADDR = '0x1111111111111111111111111111111111111111' as Address;
const USER_ADDR = '0x2222222222222222222222222222222222222222' as Address;
const WRAPPER_ADDR = '0x3333333333333333333333333333333333333333' as Address;
const FARM_ADDR = '0x4444444444444444444444444444444444444444' as Address;
const TOKEN_ADDR = '0x5555555555555555555555555555555555555555' as Address;
const NFT_ADDR = '0x6666666666666666666666666666666666666666' as Address;
const POOL_ADDR = '0x7777777777777777777777777777777777777777' as Address;

function createMockPublicClient() {
  return {
    readContract: vi.fn().mockResolvedValue(WRAPPER_ADDR),
  } as any;
}

describe('createWrapperSickle', () => {
  let wrapper: ReturnType<typeof createWrapperSickle>;
  let mockPublicClient: ReturnType<typeof createMockPublicClient>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockPublicClient = createMockPublicClient();
    wrapper = createWrapperSickle({
      wrapperFactoryAddress: FACTORY_ADDR,
      publicClient: mockPublicClient,
    });
  });

  describe('factory', () => {
    describe('getOrCreateWrapper', () => {
      it('returns calldata targeting the factory', () => {
        const result = wrapper.factory.getOrCreateWrapper(USER_ADDR);

        expect(result.functionName).toBe('getOrCreateWrapper');
        expect(result.args).toEqual([USER_ADDR]);
        expect(result.abi).toBe(wrapperFactoryAbi);
        expect(result.address).toBe(FACTORY_ADDR);
        expect(result.value).toBe(0n);
      });

      it('is synchronous', () => {
        const result = wrapper.factory.getOrCreateWrapper(USER_ADDR);
        // Should not be a Promise
        expect(result.functionName).toBeDefined();
      });
    });

    describe('predict', () => {
      it('calls readContract with correct params', async () => {
        const result = await wrapper.factory.predict(USER_ADDR);

        expect(result).toBe(WRAPPER_ADDR);
        expect(mockPublicClient.readContract).toHaveBeenCalledWith({
          address: FACTORY_ADDR,
          abi: wrapperFactoryAbi,
          functionName: 'predict',
          args: [USER_ADDR],
        });
      });
    });
  });

  describe('lp', () => {
    const baseLpParams = {
      chainId: 8453,
      userAddress: USER_ADDR,
      farmAddress: FARM_ADDR,
    };

    describe('deposit', () => {
      it('calls predict then sickle.lp.deposit with wrapperAddress', async () => {
        const params = {
          ...baseLpParams,
          amount: 1000n,
          positionSettings: {} as any,
        };

        const result = await wrapper.lp.deposit(params);

        expect(mockPublicClient.readContract).toHaveBeenCalledOnce();
        expect(sickle.lp.deposit).toHaveBeenCalledWith({
          chainId: 8453,
          walletAddress: WRAPPER_ADDR,
          farmAddress: FARM_ADDR,
          amount: 1000n,
          positionSettings: {},
        });
      });

      it('replaces address with wrapper and abi with SickleWrapper', async () => {
        const result = await wrapper.lp.deposit({
          ...baseLpParams,
          amount: 1000n,
          positionSettings: {} as any,
        });

        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });

      it('preserves functionName from SDK response', async () => {
        const result = await wrapper.lp.deposit({
          ...baseLpParams,
          amount: 1000n,
          positionSettings: {} as any,
        });

        expect(result.functionName).toBe('deposit');
      });

      it('preserves args from SDK response', async () => {
        const result = await wrapper.lp.deposit({
          ...baseLpParams,
          amount: 1000n,
          positionSettings: {} as any,
        });

        expect(result.args).toEqual(['arg0_deposit', 'arg1_deposit', 'arg2_deposit']);
      });
    });

    describe('depositToken', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.depositToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 500n,
          positionSettings: {} as any,
        });

        expect(sickle.lp.depositToken).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });

      it('passes optional slippage params', async () => {
        await wrapper.lp.depositToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 500n,
          positionSettings: {} as any,
          slippage: 0.5,
          priceImpact: 1,
        });

        expect(sickle.lp.depositToken).toHaveBeenCalledWith(
          expect.objectContaining({
            slippage: 0.5,
            priceImpact: 1,
          })
        );
      });
    });

    describe('depositUnderlying', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.depositUnderlying({
          ...baseLpParams,
          amount0: 100n,
          amount1: 200n,
          positionSettings: {} as any,
        });

        expect(sickle.lp.depositUnderlying).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('increase.withToken', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.increase.withToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 300n,
        });

        expect(sickle.lp.increase.withToken).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.functionName).toBe('increase');
      });
    });

    describe('increase.withUnderlying', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.increase.withUnderlying({
          ...baseLpParams,
          amount0: 100n,
          amount1: 200n,
          token0Address: TOKEN_ADDR,
          token1Address: NFT_ADDR,
        });

        expect(sickle.lp.increase.withUnderlying).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('harvest', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.harvest({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
        });

        expect(sickle.lp.harvest).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.functionName).toBe('harvest');
      });
    });

    describe('withdraw.toLp', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.withdraw.toLp({
          ...baseLpParams,
          amount: 1000n,
        });

        expect(sickle.lp.withdraw.toLp).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('withdraw.toToken', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.withdraw.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        expect(sickle.lp.withdraw.toToken).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('withdraw.toUnderlying', () => {
      it('swaps address/abi to target wrapper', async () => {
        const result = await wrapper.lp.withdraw.toUnderlying({
          ...baseLpParams,
          amount: 1000n,
        });

        expect(sickle.lp.withdraw.toUnderlying).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('exit.toToken', () => {
      it('calls harvest and withdraw.toToken in parallel', async () => {
        const result = await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        expect(sickle.lp.harvest).toHaveBeenCalledWith(
          expect.objectContaining({
            walletAddress: WRAPPER_ADDR,
            farmAddress: FARM_ADDR,
            tokenAddress: TOKEN_ADDR,
          })
        );
        expect(sickle.lp.withdraw.toToken).toHaveBeenCalledWith(
          expect.objectContaining({
            walletAddress: WRAPPER_ADDR,
            farmAddress: FARM_ADDR,
            tokenAddress: TOKEN_ADDR,
            amount: 1000n,
          })
        );
      });

      it('targets the wrapper with functionName exit', async () => {
        const result = await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        expect(result.functionName).toBe('exit');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.value).toBe(0n);
      });

      it('composes args from harvest and withdraw sub-calls', async () => {
        const result = await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        // args = [farm, harvestParams, harvestSweepTokens, withdrawParams, withdrawSweepTokens]
        expect(result.args).toHaveLength(5);
        // farm from harvest args[0]
        expect(result.args[0]).toBe('arg0_harvest');
        // harvestParams from harvest args[1]
        expect(result.args[1]).toBe('arg1_harvest');
        // harvestSweepTokens from harvest args[2]
        expect(result.args[2]).toBe('arg2_harvest');
        // withdrawParams from withdraw args[1]
        expect(result.args[3]).toBe('arg1_withdraw');
        // withdrawSweepTokens from withdraw args[2]
        expect(result.args[4]).toBe('arg2_withdraw');
      });

      it('sums gas estimates from both sub-calls', async () => {
        const result = await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        // Both mocks return gas: 100000n
        expect(result.gas).toBe(200000n);
      });

      it('passes optional pool params to both sub-calls', async () => {
        await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
          poolAddress: POOL_ADDR,
          poolId: 42,
          slippage: 0.5,
          priceImpact: 1,
        });

        expect(sickle.lp.harvest).toHaveBeenCalledWith(
          expect.objectContaining({
            poolAddress: POOL_ADDR,
            poolId: 42,
            slippage: 0.5,
            priceImpact: 1,
          })
        );
        expect(sickle.lp.withdraw.toToken).toHaveBeenCalledWith(
          expect.objectContaining({
            poolAddress: POOL_ADDR,
            poolId: 42,
            slippage: 0.5,
            priceImpact: 1,
          })
        );
      });

      it('returns undefined gas when either sub-call lacks gas', async () => {
        vi.mocked(sickle.lp.harvest).mockResolvedValueOnce({
          chainId: 8453,
          functionName: 'harvest',
          args: ['farm', 'params', 'sweep'],
          abi: [] as unknown as Abi,
          address: WRAPPER_ADDR,
          value: 0n,
          gas: undefined,
        });

        const result = await wrapper.lp.exit.toToken({
          ...baseLpParams,
          tokenAddress: TOKEN_ADDR,
          amount: 1000n,
        });

        expect(result.gas).toBeUndefined();
      });
    });
  });

  describe('nft', () => {
    const baseNftParams = {
      chainId: 8453,
      userAddress: USER_ADDR,
      farmAddress: FARM_ADDR,
    };

    describe('deposit', () => {
      it('calls predict then sickle.nft.deposit with wrapperAddress', async () => {
        await wrapper.nft.deposit({
          ...baseNftParams,
          nftId: 1,
          nftSettings: {} as any,
        });

        expect(sickle.nft.deposit).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
      });

      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.deposit({
          ...baseNftParams,
          nftId: 1,
          nftSettings: {} as any,
        });

        expect(result.functionName).toBe('depositNft');
      });

      it('targets the wrapper address with SickleWrapper abi', async () => {
        const result = await wrapper.nft.deposit({
          ...baseNftParams,
          nftId: 1,
          nftSettings: {} as any,
        });

        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('depositToken', () => {
      it('appends Nft to functionName and targets wrapper', async () => {
        const result = await wrapper.nft.depositToken({
          ...baseNftParams,
          tokenAddress: TOKEN_ADDR,
          amount: 500n,
          nftSettings: {} as any,
        });

        expect(result.functionName).toBe('depositNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('depositUnderlying', () => {
      it('appends Nft to functionName and targets wrapper', async () => {
        const result = await wrapper.nft.depositUnderlying({
          ...baseNftParams,
          amount0: 100n,
          amount1: 200n,
          nftSettings: {} as any,
        });

        expect(result.functionName).toBe('depositNft');
        expect(result.address).toBe(WRAPPER_ADDR);
      });
    });

    describe('increase.withToken', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.increase.withToken({
          ...baseNftParams,
          tokenAddress: TOKEN_ADDR,
          amount: 300n,
          nftId: 1,
        });

        expect(result.functionName).toBe('increaseNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('increase.withUnderlying', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.increase.withUnderlying({
          ...baseNftParams,
          amount0: 100n,
          amount1: 200n,
          nftId: 1,
        });

        expect(result.functionName).toBe('increaseNft');
        expect(result.address).toBe(WRAPPER_ADDR);
      });
    });

    describe('harvest', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.harvest({
          ...baseNftParams,
          nftId: 1,
        });

        expect(result.functionName).toBe('harvestNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('decrease.toToken', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.decrease.toToken({
          ...baseNftParams,
          positionPercentage: 50,
          nftId: 1,
        });

        expect(result.functionName).toBe('decreaseNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('decrease.toUnderlying', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.decrease.toUnderlying({
          ...baseNftParams,
          positionPercentage: 50,
          nftId: 1,
        });

        expect(result.functionName).toBe('decreaseNft');
        expect(result.address).toBe(WRAPPER_ADDR);
      });
    });

    describe('withdraw', () => {
      it('appends Nft to functionName', async () => {
        const result = await wrapper.nft.withdraw({
          ...baseNftParams,
          nftId: 1,
        });

        expect(result.functionName).toBe('simpleWithdrawNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });
    });

    describe('rebalance', () => {
      it('appends Nft to functionName and targets wrapper', async () => {
        const result = await wrapper.nft.rebalance({
          chainId: 8453,
          userAddress: USER_ADDR,
          nftId: 1,
          sourceFarmAddress: FARM_ADDR,
        });

        expect(sickle.nft.rebalance).toHaveBeenCalledWith(
          expect.objectContaining({ walletAddress: WRAPPER_ADDR })
        );
        expect(result.functionName).toBe('rebalanceNft');
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
      });

      it('does not pass userAddress to sickle-sdk', async () => {
        await wrapper.nft.rebalance({
          chainId: 8453,
          userAddress: USER_ADDR,
          nftId: 1,
          sourceFarmAddress: FARM_ADDR,
        });

        const callArgs = vi.mocked(sickle.nft.rebalance).mock.calls[0][0] as any;
        expect(callArgs.userAddress).toBeUndefined();
      });
    });
  });

  describe('rescue', () => {
    describe('token', () => {
      it('returns calldata for rescueToken on the wrapper', async () => {
        const result = await wrapper.rescue.token(8453, USER_ADDR, TOKEN_ADDR);

        expect(result.functionName).toBe('rescueToken');
        expect(result.args).toEqual([TOKEN_ADDR]);
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.chainId).toBe(8453);
        expect(result.value).toBe(0n);
      });
    });

    describe('eth', () => {
      it('returns calldata for rescueETH on the wrapper', async () => {
        const result = await wrapper.rescue.eth(8453, USER_ADDR);

        expect(result.functionName).toBe('rescueETH');
        expect(result.args).toEqual([]);
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.chainId).toBe(8453);
        expect(result.value).toBe(0n);
      });
    });

    describe('nft', () => {
      it('returns calldata for rescueNft on the wrapper', async () => {
        const result = await wrapper.rescue.nft(8453, USER_ADDR, NFT_ADDR, 42n);

        expect(result.functionName).toBe('rescueNft');
        expect(result.args).toEqual([NFT_ADDR, 42n]);
        expect(result.address).toBe(WRAPPER_ADDR);
        expect(result.abi).toBe(sickleWrapperAbi);
        expect(result.chainId).toBe(8453);
        expect(result.value).toBe(0n);
      });
    });
  });

  describe('walletAddress substitution', () => {
    it('never leaks userAddress to the sickle-sdk', async () => {
      await wrapper.lp.harvest({
        chainId: 8453,
        userAddress: USER_ADDR,
        farmAddress: FARM_ADDR,
      });

      const callArgs = vi.mocked(sickle.lp.harvest).mock.calls[0][0] as any;
      expect(callArgs.walletAddress).toBe(WRAPPER_ADDR);
      expect(callArgs.userAddress).toBeUndefined();
    });

    it('uses the wrapper address (from predict) as walletAddress', async () => {
      const differentWrapper = '0x9999999999999999999999999999999999999999' as Address;
      mockPublicClient.readContract.mockResolvedValueOnce(differentWrapper);

      const result = await wrapper.lp.harvest({
        chainId: 8453,
        userAddress: USER_ADDR,
        farmAddress: FARM_ADDR,
      });

      const callArgs = vi.mocked(sickle.lp.harvest).mock.calls[0][0] as any;
      expect(callArgs.walletAddress).toBe(differentWrapper);
      expect(result.address).toBe(differentWrapper);
    });
  });

  describe('predict is called once per operation', () => {
    it('calls readContract exactly once for an lp operation', async () => {
      await wrapper.lp.deposit({
        chainId: 8453,
        userAddress: USER_ADDR,
        farmAddress: FARM_ADDR,
        amount: 1000n,
        positionSettings: {} as any,
      });

      expect(mockPublicClient.readContract).toHaveBeenCalledTimes(1);
    });

    it('calls readContract exactly once for exit (despite two sub-calls)', async () => {
      await wrapper.lp.exit.toToken({
        chainId: 8453,
        userAddress: USER_ADDR,
        farmAddress: FARM_ADDR,
        tokenAddress: TOKEN_ADDR,
        amount: 1000n,
      });

      expect(mockPublicClient.readContract).toHaveBeenCalledTimes(1);
    });

    it('calls readContract exactly once for a rescue operation', async () => {
      await wrapper.rescue.token(8453, USER_ADDR, TOKEN_ADDR);

      expect(mockPublicClient.readContract).toHaveBeenCalledTimes(1);
    });
  });
});
