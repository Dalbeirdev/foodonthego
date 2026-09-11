<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One photograph of a restaurant.
 *
 * Customer-visible only when `is_active` is true. That flag is a moderation
 * gate rather than a soft delete: an image somebody uploaded and nobody has
 * reviewed is not something to put on a customer's screen.
 */
final class RestaurantMedia extends Model
{
    protected $table = 'restaurant_media';

    /**
     * Empty, like every other model in this schema. Media arrives from an
     * operator dashboard a later module will build, and that dashboard will
     * assign the fields it is allowed to assign by name.
     *
     * @var list<string>
     */
    protected $fillable = [];

    /**
     * Attaches one image to a restaurant.
     *
     * A named constructor rather than a `$fillable` list, because the fields
     * here are the ones an operator dashboard will eventually accept from a
     * form. Keeping `$fillable` empty means a future controller cannot pass a
     * request array straight through and accidentally let somebody set
     * `is_active` on their own upload.
     *
     * @param  array<string, mixed>  $attributes
     */
    public static function add(Restaurant $restaurant, array $attributes): self
    {
        $media = new self;

        $media->forceFill([
            'restaurant_id' => $restaurant->id,
            'url' => $attributes['url'],
            'thumbnail_url' => $attributes['thumbnail_url'] ?? null,
            'alt_text' => $attributes['alt_text'] ?? null,
            'width' => $attributes['width'] ?? null,
            'height' => $attributes['height'] ?? null,
            'position' => $attributes['position'] ?? 0,
            'is_active' => $attributes['is_active'] ?? false,
        ])->save();

        return $media;
    }

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /** @param Builder<self> $query */
    public function scopeVisible(Builder $query): void
    {
        $query->where('is_active', true)->orderBy('position')->orderBy('id');
    }

    /**
     * What a customer is told about this image.
     *
     * Returns null rather than "Image 2 of 5" when there is no caption. A
     * screen reader announcing a position tells a blind customer nothing about
     * whether they want to eat here, and the client can say something more
     * useful with the restaurant's own name than this row can.
     */
    public function caption(): ?string
    {
        $alt = trim((string) $this->alt_text);

        return $alt === '' ? null : $alt;
    }

    /** @return array<string, mixed> */
    public function toCustomerArray(): array
    {
        return [
            'id' => $this->uuid,
            'url' => $this->url,
            // Falls back to the full image rather than to null: a client that
            // asked for a thumbnail and got nothing renders a hole.
            'thumbnail_url' => $this->thumbnail_url ?: $this->url,
            'alt_text' => $this->caption(),
            'width' => $this->width === null ? null : (int) $this->width,
            'height' => $this->height === null ? null : (int) $this->height,
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $media): void {
            $media->uuid ??= (string) Str::uuid();
        });
    }

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'position' => 'integer',
        ];
    }
}
