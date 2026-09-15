import { Bell, CircleUserRound, Home, Map, ReceiptText } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

/**
 * The five customer destinations, in one place.
 *
 * One array drives the desktop rail and the phone bottom bar, so the two can
 * disagree about neither order nor wording. The labels match the Flutter app's
 * exactly — a customer who uses the phone app and the website must not have to
 * learn that "Trips" and "Journeys" are the same tab.
 */
export interface CustomerDestination {
  readonly label: string;
  readonly path: string;
  readonly icon: LucideIcon;
}

export const customerDestinations: readonly CustomerDestination[] = [
  { label: 'Home', path: '/', icon: Home },
  { label: 'Trips', path: '/trips', icon: Map },
  { label: 'Orders', path: '/orders', icon: ReceiptText },
  { label: 'Notifications', path: '/notifications', icon: Bell },
  { label: 'Profile', path: '/profile', icon: CircleUserRound },
];
