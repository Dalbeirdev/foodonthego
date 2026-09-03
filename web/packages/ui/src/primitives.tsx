import type { ReactNode, ButtonHTMLAttributes } from 'react';
import './primitives.css';

/**
 * The small set of building blocks both shells share. Deliberately narrow: a
 * component library grown ahead of the features that need it becomes a second
 * design system to maintain. These exist because Module 01's shells use them.
 */

export type Tone = 'neutral' | 'primary' | 'success' | 'warning' | 'error' | 'info';

export const Card = ({
  children,
  className = '',
  padded = true,
}: {
  children: ReactNode;
  className?: string;
  padded?: boolean;
}) => <section className={`fotg-card ${padded ? 'fotg-card--padded' : ''} ${className}`}>{children}</section>;

export const Badge = ({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) => (
  <span className={`fotg-badge fotg-badge--${tone}`}>{children}</span>
);

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  icon?: ReactNode;
};

export const Button = ({
  variant = 'secondary',
  size = 'md',
  icon,
  children,
  className = '',
  ...rest
}: ButtonProps) => (
  <button type="button" className={`fotg-button fotg-button--${variant} fotg-button--${size} ${className}`} {...rest}>
    {icon ? (
      <span className="fotg-button__icon" aria-hidden="true">
        {icon}
      </span>
    ) : null}
    {children}
  </button>
);

/**
 * The placeholder that keeps Module 01 honest.
 *
 * Every shell route that has no feature behind it yet renders this. It says so in
 * words, names the module that will deliver it, and is visually distinct from a
 * real page — so nobody reviewing the shell can mistake scaffolding for a finished
 * screen. That is a hard requirement of the module spec, not decoration.
 */
export const ModulePlaceholder = ({
  title,
  module,
  description,
  icon,
}: {
  title: string;
  module: string;
  description: string;
  icon?: ReactNode;
}) => (
  <div className="fotg-placeholder">
    <div className="fotg-placeholder__icon" aria-hidden="true">
      {icon}
    </div>
    <div className="fotg-placeholder__body">
      <div className="fotg-placeholder__heading">
        <h2>{title}</h2>
        <Badge tone="warning">Not built yet</Badge>
      </div>
      <p className="fotg-placeholder__description">{description}</p>
      <p className="fotg-placeholder__module">
        Scheduled for <strong>{module}</strong>. This screen is navigation scaffolding — it holds no
        data and calls no API.
      </p>
    </div>
  </div>
);

export const StatTile = ({
  label,
  value,
  hint,
  icon,
  tone = 'neutral',
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  icon?: ReactNode;
  tone?: Tone;
}) => (
  <div className={`fotg-stat fotg-stat--${tone}`}>
    <div className="fotg-stat__head">
      <span className="fotg-stat__label">{label}</span>
      {icon ? (
        <span className="fotg-stat__icon" aria-hidden="true">
          {icon}
        </span>
      ) : null}
    </div>
    <div className="fotg-stat__value">{value}</div>
    {hint ? <div className="fotg-stat__hint">{hint}</div> : null}
  </div>
);

export const Skeleton = ({ height = 20, width = '100%' }: { height?: number | string; width?: number | string }) => (
  <span className="fotg-skeleton" style={{ height, width }} aria-hidden="true" />
);
