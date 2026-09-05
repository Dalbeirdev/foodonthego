<?php

declare(strict_types=1);

namespace App\Services\Menu;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use Illuminate\Http\Request;

/**
 * What the customer asked of a menu.
 *
 * One parameter today — a search term — and a value object anyway, for the same
 * reason Module 08 has one: validated once, normalised once, and impossible to
 * thread through three services as a raw string somebody forgot to check.
 */
final readonly class MenuQuery
{
    public const MAX_SEARCH_LENGTH = 100;

    /**
     * Below this a search is not run.
     *
     * One character matches most of a menu and tells the customer nothing. Two
     * is the point at which "pa" starts to mean paneer rather than everything.
     */
    public const MIN_SEARCH_LENGTH = 2;

    private function __construct(public ?string $search) {}

    public static function unfiltered(): self
    {
        return new self(null);
    }

    public static function of(?string $search): self
    {
        return new self($search);
    }

    /**
     * @throws ApiException
     */
    public static function fromRequest(Request $request): self
    {
        $raw = $request->query('search');

        if (! is_string($raw)) {
            return new self(null);
        }

        // Every run of whitespace — including the tab a paste brings and the
        // non-breaking space a phone keyboard produces — becomes one space.
        $clean = trim((string) preg_replace('/\s+/u', ' ', $raw));

        if ($clean === '') {
            return new self(null);
        }

        if (mb_strlen($clean) > self::MAX_SEARCH_LENGTH) {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'That search is too long.',
                ['fields' => ['search' => [
                    'A search may be at most '.self::MAX_SEARCH_LENGTH.' characters.',
                ]]],
            );
        }

        // Shorter than the minimum is a customer mid-keystroke, not an error.
        // Treated as no search rather than answered with a validation message
        // between the first letter and the second.
        if (mb_strlen($clean) < self::MIN_SEARCH_LENGTH) {
            return new self(null);
        }

        // Punctuation only — "%%", "...", "--". The matcher folds punctuation
        // away, so such a term normalises to nothing and matches every item;
        // the response would then report the whole menu as the result for
        // "%%", which a customer would reasonably read as "these all match".
        // Treated as no search, so the menu comes back unfiltered and says so.
        if (MenuSearch::normalise($clean) === '') {
            return new self(null);
        }

        return new self($clean);
    }

    public function hasSearch(): bool
    {
        return $this->search !== null;
    }

    /** @return array<string, mixed> the query as the server understood it */
    public function toApiArray(): array
    {
        return ['search' => $this->search];
    }
}
