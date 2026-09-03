import { randomBytes, randomUUID } from 'node:crypto';

export const newId = (): string => randomUUID();

// Digits and upper-case letters minus the four that get misread when a customer
// reads a reference over the phone: I/1 and O/0.
const REFERENCE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/**
 * A short order reference with ~40 bits of entropy. It is not a secret and not the
 * primary key — it exists so a customer has something short to quote — but it is
 * random rather than sequential, so it cannot be used to count the platform's
 * orders or to walk to somebody else's.
 */
export const newOrderReference = (length = 8): string => {
  const bytes = randomBytes(length);
  let reference = '';
  for (let index = 0; index < length; index += 1) {
    reference += REFERENCE_ALPHABET[bytes[index]! % REFERENCE_ALPHABET.length];
  }
  return reference;
};
