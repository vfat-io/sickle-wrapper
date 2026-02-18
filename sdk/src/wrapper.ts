import type { Address } from 'viem';
import { encodeFunctionData } from 'viem';
import { sickle, type ContractCallData } from '@vfat-io/sickle-sdk';
import sickleWrapperAbi from './abis/SickleWrapper';
import wrapperFactoryAbi from './abis/WrapperFactory';
import type {
  WrapperConfig,
  DepositLpParams,
  DepositTokenToLpParams,
  DepositUnderlyingToLpParams,
  IncreaseLpWithTokenParams,
  IncreaseLpWithUnderlyingParams,
  HarvestLpParams,
  WithdrawLpParams,
  WithdrawLpToTokenParams,
  WithdrawLpToUnderlyingParams,
  ExitLpToTokenParams,
  DepositNftParams,
  DepositTokenToNftParams,
  DepositUnderlyingToNftParams,
  IncreaseNftWithTokenParams,
  IncreaseNftWithUnderlyingParams,
  HarvestNftParams,
  DecreaseNftToTokenParams,
  DecreaseNftToUnderlyingParams,
  WithdrawNftParams,
  RebalanceParams,
} from './types';

function wrapLpCall(
  call: ContractCallData,
  wrapperAddr: Address
): ContractCallData {
  return {
    ...call,
    address: wrapperAddr,
    abi: sickleWrapperAbi,
  };
}

function wrapNftCall(
  call: ContractCallData,
  wrapperAddr: Address
): ContractCallData {
  return {
    ...call,
    address: wrapperAddr,
    abi: sickleWrapperAbi,
    functionName: call.functionName + 'Nft',
  };
}

export function createWrapperSickle(config: WrapperConfig) {
  const { wrapperFactoryAddress, publicClient } = config;

  async function predict(userAddress: Address): Promise<Address> {
    return publicClient.readContract({
      address: wrapperFactoryAddress,
      abi: wrapperFactoryAbi,
      functionName: 'predict',
      args: [userAddress],
    }) as Promise<Address>;
  }

  async function withWrapper<P extends { userAddress: Address }>(
    params: P,
    sdkCall: (sdkParams: Omit<P, 'userAddress'> & { walletAddress: Address }) => Promise<ContractCallData>,
    wrap: (call: ContractCallData, wrapperAddr: Address) => ContractCallData
  ): Promise<ContractCallData> {
    const wrapperAddr = await predict(params.userAddress);
    const { userAddress, ...rest } = params;
    const sdkParams = { ...rest, walletAddress: wrapperAddr } as Omit<P, 'userAddress'> & { walletAddress: Address };
    const call = await sdkCall(sdkParams);
    return wrap(call, wrapperAddr);
  }

  return {
    factory: {
      getOrCreateWrapper(userAddress: Address): ContractCallData {
        return {
          chainId: 0,
          functionName: 'getOrCreateWrapper',
          args: [userAddress],
          abi: wrapperFactoryAbi,
          address: wrapperFactoryAddress,
          value: 0n,
        };
      },

      predict,
    },

    lp: {
      deposit: (params: DepositLpParams) =>
        withWrapper(params, sickle.lp.deposit, wrapLpCall),

      depositToken: (params: DepositTokenToLpParams) =>
        withWrapper(params, sickle.lp.depositToken, wrapLpCall),

      depositUnderlying: (params: DepositUnderlyingToLpParams) =>
        withWrapper(params, sickle.lp.depositUnderlying, wrapLpCall),

      increase: {
        withToken: (params: IncreaseLpWithTokenParams) =>
          withWrapper(params, sickle.lp.increase.withToken, wrapLpCall),

        withUnderlying: (params: IncreaseLpWithUnderlyingParams) =>
          withWrapper(params, sickle.lp.increase.withUnderlying, wrapLpCall),
      },

      harvest: (params: HarvestLpParams) =>
        withWrapper(params, sickle.lp.harvest, wrapLpCall),

      withdraw: {
        toLp: (params: WithdrawLpParams) =>
          withWrapper(params, sickle.lp.withdraw.toLp, wrapLpCall),

        toToken: (params: WithdrawLpToTokenParams) =>
          withWrapper(params, sickle.lp.withdraw.toToken, wrapLpCall),

        toUnderlying: (params: WithdrawLpToUnderlyingParams) =>
          withWrapper(params, sickle.lp.withdraw.toUnderlying, wrapLpCall),
      },

      exit: {
        toToken: async (params: ExitLpToTokenParams): Promise<ContractCallData> => {
          const wrapperAddr = await predict(params.userAddress);
          const { userAddress, ...rest } = params;

          const [harvestCall, withdrawCall] = await Promise.all([
            sickle.lp.harvest({
              chainId: rest.chainId,
              walletAddress: wrapperAddr,
              farmAddress: rest.farmAddress,
              tokenAddress: rest.tokenAddress,
              poolAddress: rest.poolAddress,
              poolId: rest.poolId,
              slippage: rest.slippage,
              priceImpact: rest.priceImpact,
            }),
            sickle.lp.withdraw.toToken({
              chainId: rest.chainId,
              walletAddress: wrapperAddr,
              farmAddress: rest.farmAddress,
              tokenAddress: rest.tokenAddress,
              amount: rest.amount,
              poolAddress: rest.poolAddress,
              poolId: rest.poolId,
              slippage: rest.slippage,
              priceImpact: rest.priceImpact,
            }),
          ]);

          // harvest returns args: [farm, harvestParams, sweepTokens]
          // withdraw returns args: [farm, withdrawParams, sweepTokens]
          const farm = harvestCall.args[0];
          const harvestParams = harvestCall.args[1];
          const harvestSweepTokens = harvestCall.args[2];
          const withdrawParams = withdrawCall.args[1];
          const withdrawSweepTokens = withdrawCall.args[2];

          return {
            chainId: rest.chainId,
            functionName: 'exit',
            args: [
              farm,
              harvestParams,
              harvestSweepTokens,
              withdrawParams,
              withdrawSweepTokens,
            ],
            abi: sickleWrapperAbi,
            address: wrapperAddr,
            value: 0n,
            gas: harvestCall.gas && withdrawCall.gas
              ? BigInt(harvestCall.gas.toString()) + BigInt(withdrawCall.gas.toString())
              : undefined,
          };
        },
      },
    },

    nft: {
      deposit: (params: DepositNftParams) =>
        withWrapper(params, sickle.nft.deposit, wrapNftCall),

      depositToken: (params: DepositTokenToNftParams) =>
        withWrapper(params, sickle.nft.depositToken, wrapNftCall),

      depositUnderlying: (params: DepositUnderlyingToNftParams) =>
        withWrapper(params, sickle.nft.depositUnderlying, wrapNftCall),

      increase: {
        withToken: (params: IncreaseNftWithTokenParams) =>
          withWrapper(params, sickle.nft.increase.withToken, wrapNftCall),

        withUnderlying: (params: IncreaseNftWithUnderlyingParams) =>
          withWrapper(params, sickle.nft.increase.withUnderlying, wrapNftCall),
      },

      harvest: (params: HarvestNftParams) =>
        withWrapper(params, sickle.nft.harvest, wrapNftCall),

      decrease: {
        toToken: (params: DecreaseNftToTokenParams) =>
          withWrapper(params, sickle.nft.decrease.toToken, wrapNftCall),

        toUnderlying: (params: DecreaseNftToUnderlyingParams) =>
          withWrapper(params, sickle.nft.decrease.toUnderlying, wrapNftCall),
      },

      withdraw: (params: WithdrawNftParams) =>
        withWrapper(params, sickle.nft.withdraw, wrapNftCall),

      rebalance: async (params: RebalanceParams): Promise<ContractCallData> => {
        const wrapperAddr = await predict(params.userAddress);
        const { userAddress, ...rest } = params;
        const call = await sickle.nft.rebalance({
          ...rest,
          walletAddress: wrapperAddr,
        });
        return wrapNftCall(call, wrapperAddr);
      },
    },

    rescue: {
      token: async (
        chainId: number,
        userAddress: Address,
        token: Address
      ): Promise<ContractCallData> => {
        const wrapperAddr = await predict(userAddress);
        return {
          chainId,
          functionName: 'rescueToken',
          args: [token],
          abi: sickleWrapperAbi,
          address: wrapperAddr,
          value: 0n,
        };
      },

      eth: async (
        chainId: number,
        userAddress: Address
      ): Promise<ContractCallData> => {
        const wrapperAddr = await predict(userAddress);
        return {
          chainId,
          functionName: 'rescueETH',
          args: [],
          abi: sickleWrapperAbi,
          address: wrapperAddr,
          value: 0n,
        };
      },

      nft: async (
        chainId: number,
        userAddress: Address,
        nftAddress: Address,
        tokenId: bigint
      ): Promise<ContractCallData> => {
        const wrapperAddr = await predict(userAddress);
        return {
          chainId,
          functionName: 'rescueNft',
          args: [nftAddress, tokenId],
          abi: sickleWrapperAbi,
          address: wrapperAddr,
          value: 0n,
        };
      },
    },
  };
}
