"use client";

import { formatUnits } from "viem";
import { Address } from "~~/components/scaffold-eth";
import { usePoolContract } from "~~/hooks/balancer";

/**
 * Display a pool's contract details
 * @dev do we want to display any of the pool config details? -> https://docs-v3.balancer.fi/concepts/vault/onchain-api.html#getpoolconfig
 * 
 * struct PoolConfig {
    bool isPoolRegistered;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool hasDynamicSwapFee;
    uint64 staticSwapFeePercentage; // stores an 18-decimal FP value (max FixedPoint.ONE)
    uint24 tokenDecimalDiffs; // stores 18-(token decimals), for each token
    uint32 pauseWindowEndTime;
    PoolHooks hooks;
    LiquidityManagement liquidityManagement;
    }
 */
export const PoolDetails = ({ poolAddress }: { poolAddress: string }) => {
  const { data: pool } = usePoolContract(poolAddress);

  const detailsRows = [
    { attribute: "Name", detail: pool?.name },
    { attribute: "Symbol", detail: pool?.symbol },
    { attribute: "Contract Address", detail: <Address address={pool?.address} size="lg" /> },
    { attribute: "Vault Address", detail: <Address address={pool?.vaultAddress} size="lg" /> },
    { attribute: "Total Supply", detail: formatUnits(pool?.totalSupply || 0n, pool?.decimals || 18) },
  ];
  return (
    <div className="w-full">
      <h5 className="text-2xl font-bold mb-3">Details</h5>
      <div className="overflow-x-auto rounded-lg">
        <table className="table text-lg">
          <thead>
            <tr className="text-lg bg-base-100 border-b border-accent">
              <th className="border-r border-accent">Attribute</th>
              <th>Details</th>
            </tr>
          </thead>
          <tbody className="bg-base-200">
            {detailsRows.map(({ attribute, detail }, index) => (
              <tr key={attribute} className={`${index < detailsRows.length - 1 ? "border-b border-accent" : ""}`}>
                <td className="border-r border-accent">{attribute}</td>
                <td>{detail}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};