<?php

declare(strict_types=1);

namespace App\Support\Orders;

use App\Enums\OrderStatus;

/**
 * The words a customer reads for each state, written in exactly one place.
 *
 * WHY THE SERVER OWNS THIS. A phone that decided "COOKING means your food is
 * being prepared" would have to be updated in an app-store release before the
 * lifecycle could gain a state, and until then every unreleased app would show
 * a raw enum value to a customer. Sending the sentence with the status means a
 * new state is a backend deploy.
 *
 * IT IS ALSO WHERE THE PRIVACY LINE SITS. Nothing here is derived from an
 * internal reason code, a staffing note, or an actor. The only variable text a
 * customer can receive is `orders.customer_safe_reason`, which is written
 * deliberately by whoever performs the transition and is nullable precisely so
 * that "no safe explanation exists" is expressible.
 */
final class OrderStatusCopy
{
    /**
     * The headline. Short, factual, and about the order rather than the
     * restaurant's internal situation.
     */
    public static function title(OrderStatus $status): string
    {
        return match ($status) {
            OrderStatus::Placed => 'Order placed',
            OrderStatus::Accepted => 'Restaurant accepted your order',
            OrderStatus::Cooking => 'Your food is being prepared',
            OrderStatus::Ready => 'Ready for pickup',
            OrderStatus::PickedUp => 'Picked up',
            OrderStatus::Rejected => "Restaurant couldn't accept this order",
            OrderStatus::Cancelled => 'Order cancelled',

            /*
             | Reachable only through a bug or a payment that never completed.
             |
             | A customer looking at a payment target has not bought anything,
             | and the Orders tab filters these out -- but a status map with a
             | hole in it throws where a wrong sentence would merely mislead,
             | so every case is answered.
             */
            OrderStatus::AwaitingPayment => 'Waiting for payment',
            OrderStatus::PaymentFailed => 'Payment was not completed',
            OrderStatus::Refunded => 'Refunded',
        };
    }

    /**
     * One sentence saying what happens next, or that nothing does.
     *
     * The subtitle is where a customer finds out whether they need to do
     * something. READY is the only state that asks anything of them, and it
     * says so plainly.
     */
    public static function subtitle(OrderStatus $status): string
    {
        return match ($status) {
            OrderStatus::Placed => 'Waiting for the restaurant to confirm.',
            OrderStatus::Accepted => 'The restaurant has confirmed your order.',
            OrderStatus::Cooking => 'Your food is being prepared.',
            OrderStatus::Ready => 'Show your pickup code when you arrive.',
            OrderStatus::PickedUp => 'Pickup completed.',

            /*
             | No reason, deliberately.
             |
             | Why a restaurant refused an order is between the restaurant and
             | the platform. If something customer-safe can be said, whoever
             | rejected the order writes it into customer_safe_reason and the
             | tracking response carries it separately -- it does not get
             | reverse-engineered from an internal code here.
             */
            OrderStatus::Rejected => 'This order will not be prepared.',
            OrderStatus::Cancelled => 'This order was cancelled.',

            OrderStatus::AwaitingPayment => 'No payment has been taken yet.',
            OrderStatus::PaymentFailed => 'No payment was taken.',
            OrderStatus::Refunded => 'Your money has been returned.',
        };
    }
}
