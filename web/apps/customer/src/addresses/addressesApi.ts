import { apiRequest, type ApiEnvelope } from '@fotg/ui';
import type { SavedAddress } from '../trips/tripsApi.js';

/**
 * Saved addresses, as much of Module 04's API as the trip planner needs.
 *
 * Restart Module 04 was never run for Customer Web, so this file exists because
 * Restart Module 05 requires saved Home / Work / Other to appear in the planner
 * and they cannot appear if there is no way to create one in a browser. It is
 * deliberately the *minimum* that makes that true — list, create, delete. Edit,
 * default-setting and the rest of the profile surface remain a recorded gap
 * rather than something quietly half-built here.
 */

export interface NewAddress {
  readonly type: 'HOME' | 'WORK' | 'OTHER';
  readonly label?: string | null;
  readonly address_line_1: string;
  readonly address_line_2?: string | null;
  readonly landmark?: string | null;
  readonly city: string;
  readonly state: string;
  readonly postal_code?: string | null;
  readonly country_code: string;
  /**
   * Both present or both absent.
   *
   * They come from a place the customer picked through this server's own place
   * provider — never derived from the text above. An address is a description
   * somebody wrote; a coordinate is a claim about a point on the earth, and
   * turning the first into the second by guessing is how a journey ends up
   * starting in the wrong town.
   */
  readonly latitude?: number | null;
  readonly longitude?: number | null;
  readonly place_id?: string | null;
}

interface Call {
  readonly token: string;
  readonly signal?: AbortSignal;
}

export const listAddresses = (call: Call): Promise<ApiEnvelope<SavedAddress[]>> =>
  apiRequest<SavedAddress[]>('/api/v1/customer/addresses', {
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

export const createAddress = (
  call: Call,
  address: NewAddress,
  idempotencyKey: string,
): Promise<ApiEnvelope<SavedAddress>> =>
  apiRequest<SavedAddress>('/api/v1/customer/addresses', {
    method: 'POST',
    body: address,
    idempotencyKey,
    token: call.token,
  });

export const deleteAddress = (call: Call, addressId: string): Promise<ApiEnvelope<unknown>> =>
  apiRequest<unknown>(`/api/v1/customer/addresses/${encodeURIComponent(addressId)}`, {
    method: 'DELETE',
    token: call.token,
  });
