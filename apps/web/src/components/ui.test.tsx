import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Money, QuantityStepper, StatusBadge, Totals } from './ui.js';

describe('Money', () => {
  it('renders cents as currency, never as a bare number', () => {
    render(<Money cents={3247} />);
    expect(screen.getByText('$32.47')).toBeInTheDocument();
  });

  it('renders zero as a price rather than as nothing', () => {
    render(<Money cents={0} />);
    expect(screen.getByText('$0.00')).toBeInTheDocument();
  });
});

describe('Totals', () => {
  const totals = {
    subtotalCents: 3200,
    deliveryFeeCents: 299,
    serviceFeeCents: 160,
    taxCents: 302,
    tipCents: 0,
    totalCents: 3961,
  };

  it('prints the server’s figures without re-adding them', () => {
    // A total that disagrees with its parts must still be displayed as given: the
    // server is the authority, and silently "correcting" it would hide a real bug.
    render(<Totals totals={{ ...totals, totalCents: 9999 }} />);
    expect(screen.getByText('$99.99')).toBeInTheDocument();
  });

  it('hides the tip row when there is no tip', () => {
    render(<Totals totals={totals} />);
    expect(screen.queryByText('Tip')).not.toBeInTheDocument();
  });

  it('shows the tip row when there is one', () => {
    render(<Totals totals={{ ...totals, tipCents: 480, totalCents: 4441 }} />);
    expect(screen.getByText('Tip')).toBeInTheDocument();
    expect(screen.getByText('$4.80')).toBeInTheDocument();
  });
});

describe('StatusBadge', () => {
  it('translates internal names into something a customer understands', () => {
    render(<StatusBadge status="ready_for_pickup" />);
    expect(screen.getByText('Ready — waiting for a courier')).toBeInTheDocument();
  });
});

describe('QuantityStepper', () => {
  it('steps up and down', async () => {
    const user = userEvent.setup();
    const seen: number[] = [];
    render(<QuantityStepper quantity={2} label="Margherita" onChange={(next) => seen.push(next)} />);

    await user.click(screen.getByLabelText('One more Margherita'));
    await user.click(screen.getByLabelText('One fewer Margherita'));
    expect(seen).toEqual([3, 1]);
  });

  it('says "remove" rather than "one fewer" at a quantity of one', () => {
    render(<QuantityStepper quantity={1} label="Diavola" onChange={() => {}} />);
    expect(screen.getByLabelText('Remove Diavola')).toBeInTheDocument();
  });

  it('will not step past the maximum the API accepts', () => {
    render(<QuantityStepper quantity={50} label="Marinara" onChange={() => {}} />);
    expect(screen.getByLabelText('One more Marinara')).toBeDisabled();
  });

  it('disables both controls while a request is in flight', () => {
    render(<QuantityStepper quantity={2} label="Pho" disabled onChange={() => {}} />);
    expect(screen.getByLabelText('One more Pho')).toBeDisabled();
    expect(screen.getByLabelText('One fewer Pho')).toBeDisabled();
  });
});
