/**
 * Contrato EIP-1193 simulado + inyector programático del provider.
 *
 * Restricción estructural: `injectEip1193Provider` se serializa con
 * `page.addInitScript`, por lo que NO puede referenciar helpers ni
 * constantes de módulos externos (su closure no viaja al navegador).
 * Todo el comportamiento y los datos llegan por el argumento
 * serializable `Eip1193MockBootstrap`.
 *
 * Escenarios cubiertos (docs/plan.md · Fase 3):
 * - Conexión correcta (eth_accounts, eth_requestAccounts, permissions).
 * - Cuenta bloqueada / desconectada (lista vacía + permission 4100).
 * - Rechazo de firma (4001) y de transacción (4010, código del spec).
 * - Saldo insuficiente (-32000) y red incorrecta (switch rechazado 4001).
 * - Timeout de red: método colgado sin resolver (latencia controlable).
 */

import type { Eip1193Error } from '../utils/mockData';

// ============================================================================
// Estado del wallet mockeado (serializable + mutable en página)
// ============================================================================

export interface WalletMockState {
  /** Dirección expuesta por eth_accounts (null = wallet bloqueada). */
  address: string | null;
  /** Dirección disponible al aprobar conexión cuando la wallet estaba cerrada. */
  grantableAddress: string | null;
  /** Hex chainId vigente (p. ej. '0x1'). */
  chainIdHex: string;
  /** networkVersion derivada (p. ej. '1'). */
  networkVersion: string;
  /** Si una wallet bloqueada aprueba eth_requestAccounts automáticamente. */
  autoApproveConnect: boolean;
  /** eth_sendTransaction rechaza con 4010 (spec del proyecto). */
  rejectTransaction: boolean;
  /** personal_sign/eth_sign(req) rechazan con 4001 (estándar EIP-1193). */
  rejectSignature: boolean;
  /** eth_sendTransaction falla con -32000 (mensaje geth). */
  insufficientFunds: boolean;
  /** Métodos que quedan colgados ⇒ simulación de timeout de red. */
  unresponsiveMethods: string[];
  /** Latencia artificial aplicada a TODO request (0 = inmediato). */
  latencyMs: number;
}

export interface WalletMockRpcPayloads {
  /** Dirección asociada al saldo nativo determinista. */
  readonly primaryAddressHex: string;
  readonly nativeBalanceHex: string;
  readonly zeroBalanceHex: string;
  readonly signatureHex: string;
  readonly transactionHashHex: string;
  readonly gasPriceHex: string;
  readonly blockNumberHex: string;
  readonly estimateGasHex: string;
}

/** Errores disponibles dentro del script (claves = etiquetas del preset). */
export interface WalletMockErrors {
  readonly userRejected: Eip1193Error;
  readonly userRejectedTransaction: Eip1193Error;
  readonly unauthorized: Eip1193Error;
  readonly insufficientFunds: Eip1193Error;
  readonly methodNotSupported: Eip1193Error;
}

export interface Eip1193MockBootstrap {
  readonly wallet: WalletMockState;
  readonly rpc: WalletMockRpcPayloads;
  readonly errors: WalletMockErrors;
}

// ============================================================================
// Contrato público del provider (lo que las DApps consumen)
// ============================================================================

export interface Eip1193RequestArguments {
  readonly method: string;
  readonly params?: unknown;
}

export interface Eip1193Provider {
  readonly isMetaMask: boolean;
  /** Marca de control interno: permite diferenciar el mock de un provider real. */
  readonly isDexfloMock: boolean;
  networkVersion: string;
  selectedAddress: string | null;
  chainId: string;
  request(args: Eip1193RequestArguments): Promise<unknown>;
  on(event: string, listener: (payload: unknown) => void): void;
  once(event: string, listener: (payload: unknown) => void): void;
  removeListener(event: string, listener: (payload: unknown) => void): void;
}

/** Canal de control (NO estándar) para dirigir el mock desde los tests. */
export interface DexfloWalletController {
  /** Copia del estado vigente (a prueba de mutaciones externas). */
  state(): WalletMockState;
  /** Fusiona un parche y emite accountsChanged/chainChanged si aplican. */
  configure(patch: Partial<WalletMockState>): void;
  /** Emite un evento EIP-1193 hacia los listeners registrados en página. */
  emit(event: string, payload: unknown): void;
}

declare global {
  interface Window {
    ethereum?: Eip1193Provider;
    __dexfloWallet?: DexfloWalletController;
    /** Bucket auxiliar para capturar eventos EIP-1193 en tests del provider. */
    __dexfloEvents?: unknown[];
  }
}

// ============================================================================
// Inyector del provider (autocontenido: nada del módulo puede ser referenciado)
// ============================================================================

export function injectEip1193Provider(bootstrap: Eip1193MockBootstrap): void {
  const state: WalletMockState = bootstrap.wallet;
  const rpc = bootstrap.rpc;
  const errors = bootstrap.errors;

  const listenersByEvent = new Map<string, Set<(payload: unknown) => void>>();
  // Mapa de suscripciones once: callback original → wrapper (para que
  // removeListener pueda resolver la baja desde cualquiera de las dos
  // identidades, sin depender del global vigente en cada dispatch).
  const onceWrappers = new Map<(payload: unknown) => void, (payload: unknown) => void>();

  const dispatchEvent = (event: string, payload: unknown): void => {
    const listeners = listenersByEvent.get(event);
    if (listeners === undefined) {
      return;
    }
    for (const listener of listeners) {
      try {
        listener(payload);
      } catch {
        // Aislamiento por listener: un throw de contenido de página no corta
        // la entrega al resto de suscriptores ni escapa del dispatch hacia
        // el caller de emit/configure/request.
      }
    }
  };

  const providerError = (source: Eip1193Error): Error => {
    const thrown = new Error(source.message) as Error & { code: number };
    thrown.code = source.code;
    return thrown;
  };

  const buildPermissionsPayload = (invoker: string): unknown[] => [
    {
      id: 'dexflo-mock-permission-0',
      parentCapability: 'eth_accounts',
      invoker: `dapp://${invoker}`,
      caveats: [],
      date: 0,
    },
  ];

  const sameHex = (left: string | null, right: string): boolean => {
    if (left === null) {
      return false;
    }
    return left.toLowerCase() === right.toLowerCase();
  };

  // Parseo inline de chainId hex (la restricción de serialización de
  // addInitScript impide importar toHexChainId desde src/config/networks.ts).
  // Los códigos 4902/-32602 replican RPC_ERROR_CODES.chainUnrecognized /
  // invalidInput de src/utils/mockData.ts, que el inyector no puede importar.
  const parseHexChainId = (value: unknown): number | null => {
    if (typeof value !== 'string' || !/^0[xX][0-9a-fA-F]+$/.test(value)) {
      return null;
    }
    const parsed = Number.parseInt(value, 16);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
  };

  /** Envuelve los datos deterministas en el payload de un receipt exitoso. */
  const buildReceiptPayload = (): Record<string, unknown> => ({
    transactionHash: rpc.transactionHashHex,
    from: state.address,
    status: '0x1',
    blockNumber: rpc.blockNumberHex,
    gasUsed: '0x5208', // 21000 gas: transferencia estándar
    logs: [],
  });

  const resolveRequest = (method: string, params: readonly unknown[]): unknown => {
    switch (method) {
      case 'eth_accounts':
        return state.address ? [state.address] : [];
      case 'eth_coinbase':
        return state.address ?? null;
      case 'eth_requestAccounts': {
        if (state.address) {
          return [state.address];
        }
        if (state.autoApproveConnect && state.grantableAddress) {
          state.address = state.grantableAddress;
          dispatchEvent('accountsChanged', [state.address]);
          return [state.address];
        }
        return [];
      }
      case 'wallet_requestPermissions': {
        const invoker = state.address ?? (state.autoApproveConnect ? state.grantableAddress : null);
        if (!invoker) {
          throw providerError(errors.unauthorized);
        }
        if (!state.address && state.grantableAddress) {
          state.address = state.grantableAddress;
          dispatchEvent('accountsChanged', [state.address]);
        }
        return buildPermissionsPayload(invoker);
      }
      case 'wallet_getPermissions': {
        const invoker = state.address ?? (state.autoApproveConnect ? state.grantableAddress : null);
        if (!invoker) {
          throw providerError(errors.unauthorized);
        }
        return buildPermissionsPayload(invoker);
      }
      case 'wallet_revokePermissions':
        if (state.address) {
          state.address = null;
          dispatchEvent('accountsChanged', []);
        }
        // La revocación persiste: sin esto, wallet_getPermissions/wallet_requestPermissions
        // re-derivan el permiso de autoApproveConnect y fabrican una concesión activa
        // tras el revoke, y eth_requestAccounts re-aprueba en silencio.
        state.autoApproveConnect = false;
        return null;
      case 'eth_chainId':
        return state.chainIdHex;
      case 'net_version':
        return state.networkVersion;
      case 'wallet_switchEthereumChain': {
        const raw =
          params.length > 0 && typeof params[0] === 'object' && params[0] !== null
            ? (params[0] as { chainId?: unknown }).chainId
            : undefined;
        if (typeof raw !== 'string') {
          throw providerError({ code: -32602, message: 'Invalid method parameter.' });
        }
        const parsed = parseHexChainId(raw);
        if (parsed === null) {
          throw providerError({ code: 4902, message: 'Unrecognized chain ID.' });
        }
        if (parsed === parseHexChainId(state.chainIdHex)) {
          return null; // misma cadena en cualquier forma hex: éxito idempotente (comparación numérica)
        }
        throw providerError(errors.userRejected); // 4001: otra cadena reconocida (diseño del mock)
      }
      case 'personal_sign':
      case 'eth_sign':
      case 'eth_signTypedData_v4': {
        // Contrato :12: sin cuenta conectada ⇒ 4100 (mismo gate que wallet_*Permissions).
        if (!state.address) {
          throw providerError(errors.unauthorized);
        }
        const signerIndex = method === 'personal_sign' ? 1 : 0;
        const signer = params[signerIndex];
        if (typeof signer === 'string' && signer.length > 0 && !sameHex(signer, state.address)) {
          throw providerError(errors.unauthorized);
        }
        if (state.rejectSignature) {
          throw providerError(errors.userRejected);
        }
        return rpc.signatureHex;
      }
      case 'eth_sendTransaction': {
        // Contrato :12: sin cuenta conectada ⇒ 4100; el from declarado debe ser la cuenta expuesta.
        if (!state.address) {
          throw providerError(errors.unauthorized);
        }
        const tx = params[0];
        const from =
          tx !== null && typeof tx === 'object' && 'from' in tx
            ? (tx as { from?: unknown }).from
            : null;
        if (typeof from === 'string' && from.length > 0 && !sameHex(from, state.address)) {
          throw providerError(errors.unauthorized);
        }
        if (state.rejectTransaction) {
          throw providerError(errors.userRejectedTransaction);
        }
        if (state.insufficientFunds) {
          throw providerError(errors.insufficientFunds);
        }
        return rpc.transactionHashHex;
      }
      case 'eth_estimateGas':
        return rpc.estimateGasHex;
      case 'eth_gasPrice':
        return rpc.gasPriceHex;
      case 'eth_blockNumber':
        return rpc.blockNumberHex;
      case 'eth_getBalance': {
        const requested = typeof params[0] === 'string' ? params[0] : null;
        const isWallet = sameHex(requested, state.address ?? '_____');
        const isAnchor = sameHex(requested, rpc.primaryAddressHex);
        return isWallet || isAnchor ? rpc.nativeBalanceHex : rpc.zeroBalanceHex;
      }
      case 'eth_getTransactionReceipt':
        return buildReceiptPayload();
      default:
        throw providerError(errors.methodNotSupported);
    }
  };

  window.ethereum = {
    isMetaMask: true,
    isDexfloMock: true,
    get chainId(): string {
      return state.chainIdHex;
    },
    get networkVersion(): string {
      return state.networkVersion;
    },
    get selectedAddress(): string | null {
      return state.address;
    },
    request: async (args: Eip1193RequestArguments): Promise<unknown> => {
      const method = args.method;
      const params = Array.isArray(args.params) ? (args.params as readonly unknown[]) : [];
      if (state.unresponsiveMethods.includes(method)) {
        // Sin resolución: la DApp/tests deben aplicar su propio timeout.
        return new Promise<never>(() => {
          /* pendiente a propósito: simula timeout de red */
        });
      }
      if (state.latencyMs > 0) {
        await new Promise<void>((resolve) => {
          setTimeout(resolve, state.latencyMs);
        });
      }
      return resolveRequest(method, params);
    },
    on: (event: string, listener: (payload: unknown) => void): void => {
      const listeners = listenersByEvent.get(event) ?? new Set<(payload: unknown) => void>();
      listeners.add(listener);
      listenersByEvent.set(event, listeners);
    },
    once: (event: string, listener: (payload: unknown) => void): void => {
      // Captura la instancia registrante: registro y baja operan sobre el
      // mapa dueño de la suscripción, no sobre el global vigente en cada
      // dispatch (la reasignación de window.ethereum ya no desincroniza).
      const owner = window.ethereum;
      if (!owner) {
        return;
      }
      const wrapper = (payload: unknown): void => {
        owner.removeListener(event, wrapper);
        listener(payload);
      };
      onceWrappers.set(listener, wrapper);
      owner.on(event, wrapper);
    },
    removeListener: (event: string, listener: (payload: unknown) => void): void => {
      const set = listenersByEvent.get(event);
      if (set === undefined) {
        return;
      }
      const wrapper = onceWrappers.get(listener);
      if (wrapper !== undefined) {
        onceWrappers.delete(listener);
        set.delete(wrapper);
        return;
      }
      set.delete(listener);
    },
  };

  // Canal de control para `page.evaluate` desde los tests.
  window.__dexfloWallet = {
    state: (): WalletMockState => ({
      ...state,
      unresponsiveMethods: [...state.unresponsiveMethods],
    }),
    configure: (patch: Partial<WalletMockState>): void => {
      const previousAddress = state.address;
      const previousChainIdHex = state.chainIdHex;
      Object.assign(state, patch);
      if (previousChainIdHex !== state.chainIdHex) {
        dispatchEvent('chainChanged', state.chainIdHex);
      }
      if (previousAddress !== state.address) {
        dispatchEvent('accountsChanged', state.address ? [state.address] : []);
      }
    },
    emit: dispatchEvent,
  } satisfies DexfloWalletController;
}
