import {
  BarChart3,
  CalendarClock,
  ClipboardList,
  LayoutDashboard,
  LifeBuoy,
  Settings,
  Star,
  Store,
  UtensilsCrossed,
  Users,
  Wallet,
} from 'lucide-react';
import type { NavSection } from '@fotg/ui';

/**
 * Restaurant dashboard information architecture.
 *
 * Grouped by what a restaurant actually does — take orders today, keep the menu
 * right, run the business — rather than as one flat list of eleven links. Every
 * entry names the module that will deliver it; none is implemented in Module 01.
 */
export const restaurantNavigation: NavSection[] = [
  {
    items: [
      {
        label: 'Overview',
        path: '/',
        icon: LayoutDashboard,
        module: 'Module 12 — Restaurant Analytics',
        description:
          'Today at a glance: orders due in the next hour, kitchen load against expected arrivals, and how close the last hundred orders came to being ready on time.',
      },
    ],
  },
  {
    title: 'Service',
    items: [
      {
        label: 'Orders',
        path: '/orders',
        icon: ClipboardList,
        module: 'Module 08 — Order Lifecycle',
        description:
          'The live queue, sorted by when the traveller is expected rather than when the order was placed — which is the whole point of FoodOnTheGo.',
      },
      {
        label: 'Availability',
        path: '/availability',
        icon: CalendarClock,
        module: 'Module 07 — Restaurant Availability',
        description:
          'Opening hours, kitchen capacity per slot, and pausing new orders when the kitchen is underwater.',
      },
    ],
  },
  {
    title: 'Catalogue',
    items: [
      {
        label: 'Menu',
        path: '/menu',
        icon: UtensilsCrossed,
        module: 'Module 06 — Menu Management',
        description:
          'Categories, items, prices, modifiers and per-item preparation times. Prep time feeds the ETA engine, so it is a first-class field here, not a note.',
      },
      {
        label: 'Restaurant',
        path: '/restaurant',
        icon: Store,
        module: 'Module 05 — Restaurant Profile',
        description:
          'Location, contact details, cuisine, photographs, and the highway access notes a driver needs to actually find the place.',
      },
      {
        label: 'Staff',
        path: '/staff',
        icon: Users,
        module: 'Module 04 — Staff & Roles',
        description:
          'Invite managers and kitchen staff and control what each can see. Enforced server-side by role, never by hiding buttons.',
      },
    ],
  },
  {
    title: 'Business',
    items: [
      {
        label: 'Earnings',
        path: '/earnings',
        icon: Wallet,
        module: 'Module 11 — Payments & Settlements',
        description: 'Settlements, commission, adjustments and payout history, reconciled against orders.',
      },
      {
        label: 'Reports',
        path: '/reports',
        icon: BarChart3,
        module: 'Module 12 — Restaurant Analytics',
        description: 'Sales, popular items, on-time performance and busiest routes, exportable.',
      },
      {
        label: 'Reviews',
        path: '/reviews',
        icon: Star,
        module: 'Module 13 — Reviews & Ratings',
        description: 'Customer ratings and replies, with the order each review refers to.',
      },
    ],
  },
  {
    title: 'Account',
    items: [
      {
        label: 'Support',
        path: '/support',
        icon: LifeBuoy,
        module: 'Module 14 — Support',
        description: 'Raise and track tickets with the FoodOnTheGo platform team.',
      },
      {
        label: 'Settings',
        path: '/settings',
        icon: Settings,
        module: 'Module 03 — Account Settings',
        description: 'Notification preferences, printer and device setup, and account security.',
      },
    ],
  },
];
