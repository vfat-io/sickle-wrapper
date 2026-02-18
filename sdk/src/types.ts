import type { Address } from 'viem';
import type {
  DepositLpParams as SdkDepositLpParams,
  DepositTokenToLpParams as SdkDepositTokenToLpParams,
  DepositUnderlyingToLpParams as SdkDepositUnderlyingToLpParams,
  IncreaseLpWithTokenParams as SdkIncreaseLpWithTokenParams,
  IncreaseLpWithUnderlyingParams as SdkIncreaseLpWithUnderlyingParams,
  HarvestLpParams as SdkHarvestLpParams,
  WithdrawLpParams as SdkWithdrawLpParams,
  WithdrawLpToTokenParams as SdkWithdrawLpToTokenParams,
  WithdrawLpToUnderlyingParams as SdkWithdrawLpToUnderlyingParams,
  ExitLpToTokenParams as SdkExitLpToTokenParams,
  DepositNftParams as SdkDepositNftParams,
  DepositTokenToNftParams as SdkDepositTokenToNftParams,
  DepositUnderlyingToNftParams as SdkDepositUnderlyingToNftParams,
  IncreaseNftWithTokenParams as SdkIncreaseNftWithTokenParams,
  IncreaseNftWithUnderlyingParams as SdkIncreaseNftWithUnderlyingParams,
  HarvestNftParams as SdkHarvestNftParams,
  DecreaseNftToTokenParams as SdkDecreaseNftToTokenParams,
  DecreaseNftToUnderlyingParams as SdkDecreaseNftToUnderlyingParams,
  WithdrawNftParams as SdkWithdrawNftParams,
  RebalanceParams as SdkRebalanceParams,
  ContractCallData,
} from '@vfat-io/sickle-sdk';
import type { PublicClient } from 'viem';

export type { ContractCallData } from '@vfat-io/sickle-sdk';

type ReplaceWalletWithUser<T> = Omit<T, 'walletAddress'> & {
  userAddress: Address;
};

// LP param types
export type DepositLpParams = ReplaceWalletWithUser<SdkDepositLpParams>;
export type DepositTokenToLpParams =
  ReplaceWalletWithUser<SdkDepositTokenToLpParams>;
export type DepositUnderlyingToLpParams =
  ReplaceWalletWithUser<SdkDepositUnderlyingToLpParams>;
export type IncreaseLpWithTokenParams =
  ReplaceWalletWithUser<SdkIncreaseLpWithTokenParams>;
export type IncreaseLpWithUnderlyingParams =
  ReplaceWalletWithUser<SdkIncreaseLpWithUnderlyingParams>;
export type HarvestLpParams = ReplaceWalletWithUser<SdkHarvestLpParams>;
export type WithdrawLpParams = ReplaceWalletWithUser<SdkWithdrawLpParams>;
export type WithdrawLpToTokenParams =
  ReplaceWalletWithUser<SdkWithdrawLpToTokenParams>;
export type WithdrawLpToUnderlyingParams =
  ReplaceWalletWithUser<SdkWithdrawLpToUnderlyingParams>;
export type ExitLpToTokenParams =
  ReplaceWalletWithUser<SdkExitLpToTokenParams>;

// NFT param types
export type DepositNftParams = ReplaceWalletWithUser<SdkDepositNftParams>;
export type DepositTokenToNftParams =
  ReplaceWalletWithUser<SdkDepositTokenToNftParams>;
export type DepositUnderlyingToNftParams =
  ReplaceWalletWithUser<SdkDepositUnderlyingToNftParams>;
export type IncreaseNftWithTokenParams =
  ReplaceWalletWithUser<SdkIncreaseNftWithTokenParams>;
export type IncreaseNftWithUnderlyingParams =
  ReplaceWalletWithUser<SdkIncreaseNftWithUnderlyingParams>;
export type HarvestNftParams = ReplaceWalletWithUser<SdkHarvestNftParams>;
export type DecreaseNftToTokenParams =
  ReplaceWalletWithUser<SdkDecreaseNftToTokenParams>;
export type DecreaseNftToUnderlyingParams =
  ReplaceWalletWithUser<SdkDecreaseNftToUnderlyingParams>;
export type WithdrawNftParams = ReplaceWalletWithUser<SdkWithdrawNftParams>;
export type RebalanceParams = ReplaceWalletWithUser<SdkRebalanceParams>;

export type WrapperConfig = {
  wrapperFactoryAddress: Address;
  publicClient: PublicClient;
};
