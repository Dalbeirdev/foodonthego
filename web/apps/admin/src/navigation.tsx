import {
  Activity,
  BadgePercent,
  BarChart3,
  ClipboardList,
  CreditCard,
  LayoutDashboard,
  LifeBuoy,
  Route as RouteIcon,
  ScrollText,
  Settings,
  ShieldCheck,
  Star,
  Store,
  Users,
} from 'lucide-react';
import type { NavSection } from '@fotg/ui';

/**
 * Platform admin information architecture.
 *
 * Grouped by what an operator is doing when they open the panel: looking after
 * people, looking after money, or looking after the platform itself. Every entry
 * names the module that will deliver it; none is implemented in Module 01.
 */
export const adminNavigation: NavSection[] = [
  {
    items: [
      {
        label: 'Overview',
        path: '/',
        icon: LayoutDashboard,
        module: 'Module 15 — Platform Analytics',
        description:
          'Platform health: orders in flight, ETA accuracy across live journeys, restaurants accepting orders, and anything currently failing.',
      },
    ],
  },
  {
    title: 'Marketplace',
    items: [
      {
        label: 'Customers',
        path: '/customers',
        icon: Users,
        module: 'Module 04 — Customer Administration',
        description: 'Accounts, journeys, order history and support context for one traveller.',
      },
      {
        label: 'Restaurants',
        path: '/restaurants',
        icon: Store,
        module: 'Module 05 — Restaurant Onboarding',
        description:
          'Applications, verification, commission terms and suspension. A restaurant only becomes visible on a route once it is verified here.',
      },
      {
        label: 'Routes',
        path: '/routes',
        icon: RouteIcon,
        module: 'Module 09 — Route & Corridor Management',
        description:
          'Highway corridors, catchment around each route, and the detour tolerance that decides whether a restaurant counts as "on the way".',
      },
      {
        label: 'Orders',
        path: '/orders',
        icon: ClipboardList,
        module: 'Module 08 — Order Lifecycle',
        description: 'Every order across the platform, with its ETA history and status timeline.',
      },
    ],
  },
  {
    title: 'Money',
    items: [
      {
        label: 'Payments',
        path: '/payments',
        icon: CreditCard,
        module: 'Module 11 — Payments & Settlements',
        description: 'Transactions, refunds, settlements and payouts. MySQL is the source of truth for all of it.',
      },
      {
        label: 'Promotions',
        path: '/promotions',
        icon: BadgePercent,
        module: 'Module 16 — Promotions',
        description: 'Discount codes, campaigns and who funds each one.',
      },
    ],
  },
  {
    title: 'Operations',
    items: [
      {
        label: 'Reviews',
        path: '/reviews',
        icon: Star,
        module: 'Module 13 — Reviews & Ratings',
        description: 'Moderation queue and reported reviews.',
      },
      {
        label: 'Support',
        path: '/support',
        icon: LifeBuoy,
        module: 'Module 14 — Support',
        description: 'Ticket queue across customers and restaurants.',
      },
      {
        label: 'Analytics',
        path: '/analytics',
        icon: BarChart3,
        module: 'Module 15 — Platform Analytics',
        description: 'Growth, retention, corridor performance and ETA accuracy over time.',
      },
    ],
  },
  {
    title: 'Platform',
    items: [
      {
        label: 'Administration',
        path: '/administration',
        icon: ShieldCheck,
        module: 'Module 04 — Roles & Permissions',
        description: 'Platform staff accounts and role assignment across the seven roles.',
      },
      {
        label: 'Settings',
        path: '/settings',
        icon: Settings,
        module: 'Module 17 — Platform Configuration',
        description: 'Commission defaults, ETA tuning parameters, feature flags and integration keys.',
      },
      {
        label: 'Audit Logs',
        path: '/audit-logs',
        icon: ScrollText,
        module: 'Module 18 — Audit & Compliance',
        description:
          'Append-only record of every administrative action, including who read a customer record.',
      },
      {
        label: 'System Health',
        path: '/system-health',
        icon: Activity,
        module: 'Module 01 — Foundation',
        description: 'Live readiness of the API, MySQL and Redis, read from /api/v1/health/ready.',
        implemented: true,
      },
    ],
  },
];
