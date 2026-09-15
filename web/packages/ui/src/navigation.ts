import type { LucideIcon } from 'lucide-react';

/**
 * The navigation architecture for a shell.
 *
 * Every item names the module that will fill it. Module 01 builds the structure so
 * later modules attach a real screen to an existing route rather than reorganising
 * the whole information architecture each time one lands.
 */
export interface NavItem {
  label: string;
  path: string;
  icon: LucideIcon;
  /** Which module delivers the real screen. Rendered on the placeholder. */
  module: string;
  description: string;
  /** True once a real feature is behind it. Drives the "scaffolding" affordance. */
  implemented?: boolean;
}

export interface NavSection {
  /** Undefined for the first group, which needs no heading. */
  title?: string;
  items: NavItem[];
}
