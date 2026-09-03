import { loadConfig } from '../config.js';
import { createDb } from './client.js';
import { runMigrations } from './migrate.js';
import { newId } from '../lib/ids.js';
import { hashPassword } from '../lib/password.js';
import { menuCategories, menuItems, openingHours, restaurants, users } from './schema.js';

/**
 * Development seed data. Everything here is invented; the demo accounts all share
 * one obvious password because they are meant to be signed into by hand, and the
 * script refuses to run against a production configuration.
 */
const DEMO_PASSWORD = 'foodonthego-demo';

interface SeedItem {
  name: string;
  description: string;
  priceCents: number;
  dietaryTags?: string[];
  isAvailable?: boolean;
}

interface SeedRestaurant {
  name: string;
  description: string;
  cuisine: string;
  city: string;
  region: string;
  addressLine1: string;
  postalCode: string;
  deliveryFeeCents: number;
  minimumOrderCents: number;
  prepTimeMinutes: number;
  ratingSum: number;
  ratingCount: number;
  /** [weekday, opens, closes] in minutes from midnight; closes <= opens runs overnight. */
  hours: Array<[number, number, number]>;
  categories: Array<{ name: string; description?: string; items: SeedItem[] }>;
}

const hour = (h: number, m = 0) => h * 60 + m;
const everyDay = (opens: number, closes: number): Array<[number, number, number]> =>
  [0, 1, 2, 3, 4, 5, 6].map((weekday) => [weekday, opens, closes]);

const DATA: SeedRestaurant[] = [
  {
    name: 'Sopra Pizzeria',
    description: 'Wood-fired Neapolitan pizza, a short list done properly.',
    cuisine: 'pizza',
    city: 'Springfield',
    region: 'IL',
    addressLine1: '414 Kiln Row',
    postalCode: '62701',
    deliveryFeeCents: 299,
    minimumOrderCents: 1500,
    prepTimeMinutes: 22,
    ratingSum: 1284,
    ratingCount: 281,
    hours: everyDay(hour(11), hour(23)),
    categories: [
      {
        name: 'Pizza',
        description: 'Sixty seconds at 450°C.',
        items: [
          { name: 'Margherita', description: 'San Marzano, fior di latte, basil.', priceCents: 1450, dietaryTags: ['vegetarian'] },
          { name: 'Diavola', description: 'Spicy salami, chilli honey, oregano.', priceCents: 1750, dietaryTags: ['spicy'] },
          { name: 'Marinara', description: 'Tomato, garlic, oregano, no cheese.', priceCents: 1250, dietaryTags: ['vegan'] },
          { name: 'Quattro Formaggi', description: 'Four cheeses, cracked pepper.', priceCents: 1850, dietaryTags: ['vegetarian'] },
        ],
      },
      {
        name: 'Sides & sweets',
        items: [
          { name: 'Rocket & parmesan salad', description: 'Lemon, olive oil.', priceCents: 750, dietaryTags: ['vegetarian', 'gluten_free'] },
          { name: 'Tiramisù', description: 'Made this morning.', priceCents: 850, dietaryTags: ['vegetarian'] },
        ],
      },
    ],
  },
  {
    name: 'Hanoi Corner',
    description: 'Pho simmered overnight, banh mi on bread baked at six.',
    cuisine: 'vietnamese',
    city: 'Springfield',
    region: 'IL',
    addressLine1: '77 Lantern Street',
    postalCode: '62702',
    deliveryFeeCents: 199,
    minimumOrderCents: 1200,
    prepTimeMinutes: 18,
    ratingSum: 2166,
    ratingCount: 462,
    hours: everyDay(hour(10, 30), hour(21, 30)),
    categories: [
      {
        name: 'Pho',
        items: [
          { name: 'Pho bo', description: 'Beef brisket, rice noodles, herbs.', priceCents: 1395 },
          { name: 'Pho ga', description: 'Poached chicken, ginger broth.', priceCents: 1295 },
          { name: 'Pho chay', description: 'Mushroom and charred onion broth.', priceCents: 1195, dietaryTags: ['vegan'] },
        ],
      },
      {
        name: 'Banh mi',
        items: [
          { name: 'Classic pork banh mi', description: 'Pâté, pickled carrot, coriander.', priceCents: 995 },
          { name: 'Lemongrass tofu banh mi', description: 'Chilli, cucumber, mayo.', priceCents: 925, dietaryTags: ['vegetarian'] },
        ],
      },
    ],
  },
  {
    name: 'Ember & Ash',
    description: 'Charcoal grill. Everything cooked over fire, nothing over eleven minutes.',
    cuisine: 'burgers',
    city: 'Springfield',
    region: 'IL',
    addressLine1: '3 Foundry Lane',
    postalCode: '62703',
    deliveryFeeCents: 449,
    minimumOrderCents: 0,
    prepTimeMinutes: 30,
    ratingSum: 559,
    ratingCount: 132,
    // Open into the small hours: Fri and Sat 17:00 -> 02:00 the next morning.
    hours: [
      [1, hour(17), hour(23)],
      [2, hour(17), hour(23)],
      [3, hour(17), hour(23)],
      [4, hour(17), hour(23)],
      [5, hour(17), hour(2)],
      [6, hour(17), hour(2)],
    ],
    categories: [
      {
        name: 'From the grill',
        items: [
          { name: 'Ash cheeseburger', description: 'Dry-aged patty, aged cheddar, pickles.', priceCents: 1395 },
          { name: 'Double ember', description: 'Two patties, smoked onion, house sauce.', priceCents: 1795 },
          { name: 'Charred mushroom burger', description: 'King oyster, garlic emulsion.', priceCents: 1345, dietaryTags: ['vegetarian'] },
          { name: 'Half chicken', description: 'Brined 24 hours, lemon and thyme.', priceCents: 1995, dietaryTags: ['gluten_free'] },
        ],
      },
      {
        name: 'Sides',
        items: [
          { name: 'Beef-fat fries', description: 'Rosemary salt.', priceCents: 550 },
          { name: 'Burnt-end mac', description: 'Three cheeses, brisket ends.', priceCents: 795 },
          { name: 'Slaw', description: 'Cider vinegar, no mayo.', priceCents: 450, dietaryTags: ['vegan', 'gluten_free'] },
          { name: 'Seasonal special', description: 'Ask the kitchen.', priceCents: 650, isAvailable: false },
        ],
      },
    ],
  },
  {
    name: 'Kadai Green',
    description: 'North Indian home cooking. Everything vegetarian, most of it vegan.',
    cuisine: 'indian',
    city: 'Springfield',
    region: 'IL',
    addressLine1: '210 Marigold Way',
    postalCode: '62704',
    deliveryFeeCents: 249,
    minimumOrderCents: 1800,
    prepTimeMinutes: 35,
    ratingSum: 1830,
    ratingCount: 391,
    hours: everyDay(hour(12), hour(22)),
    categories: [
      {
        name: 'Curries',
        items: [
          { name: 'Dal makhani', description: 'Black lentils, twelve hours.', priceCents: 1250, dietaryTags: ['vegetarian', 'gluten_free'] },
          { name: 'Chana masala', description: 'Chickpeas, tomato, amchur.', priceCents: 1150, dietaryTags: ['vegan', 'gluten_free'] },
          { name: 'Paneer jalfrezi', description: 'Peppers, cumin, green chilli.', priceCents: 1395, dietaryTags: ['vegetarian', 'spicy'] },
        ],
      },
      {
        name: 'Breads & rice',
        items: [
          { name: 'Garlic naan', description: 'Tandoor-baked.', priceCents: 395, dietaryTags: ['vegetarian'] },
          { name: 'Jeera rice', description: 'Basmati, cumin.', priceCents: 450, dietaryTags: ['vegan', 'gluten_free'] },
        ],
      },
    ],
  },
];

const main = async (): Promise<void> => {
  const config = loadConfig();

  if (config.nodeEnv === 'production') {
    console.error(
      '\nRefusing to seed a production database.\n\n' +
        '  This script creates demo accounts with a published password. Set NODE_ENV\n' +
        '  to development if this is a local database.\n',
    );
    process.exit(1);
  }

  const { db, sqlite, close } = createDb(config.databaseFile);
  runMigrations(sqlite);

  const existing = await db.select({ id: restaurants.id }).from(restaurants).limit(1);
  if (existing.length > 0) {
    console.log('Database already has restaurants; leaving it alone. Delete the file to reseed.');
    close();
    return;
  }

  const timestamp = new Date().toISOString();
  const passwordHash = await hashPassword(DEMO_PASSWORD);

  const owner = {
    id: newId(),
    email: 'owner@foodonthego.test',
    passwordHash,
    fullName: 'Ola Restaurateur',
    phone: '+1 555 0100',
    role: 'restaurant_owner',
    createdAt: timestamp,
    updatedAt: timestamp,
  };
  const customer = { ...owner, id: newId(), email: 'customer@foodonthego.test', fullName: 'Cam Customer', role: 'customer' };
  const courier = { ...owner, id: newId(), email: 'courier@foodonthego.test', fullName: 'Kit Courier', role: 'courier' };

  await db.insert(users).values([owner, customer, courier]);

  for (const entry of DATA) {
    const restaurantId = newId();

    await db.insert(restaurants).values({
      id: restaurantId,
      ownerId: owner.id,
      name: entry.name,
      description: entry.description,
      cuisine: entry.cuisine,
      phone: '+1 555 0111',
      addressLine1: entry.addressLine1,
      city: entry.city,
      region: entry.region,
      postalCode: entry.postalCode,
      latitude: null,
      longitude: null,
      deliveryFeeCents: entry.deliveryFeeCents,
      minimumOrderCents: entry.minimumOrderCents,
      prepTimeMinutes: entry.prepTimeMinutes,
      imageUrl: null,
      isActive: true,
      ratingSum: entry.ratingSum,
      ratingCount: entry.ratingCount,
      createdAt: timestamp,
      updatedAt: timestamp,
    });

    for (const [weekday, opensMinute, closesMinute] of entry.hours) {
      await db.insert(openingHours).values({ id: newId(), restaurantId, weekday, opensMinute, closesMinute });
    }

    for (const [categoryIndex, category] of entry.categories.entries()) {
      const categoryId = newId();
      await db.insert(menuCategories).values({
        id: categoryId,
        restaurantId,
        name: category.name,
        description: category.description ?? null,
        sortOrder: categoryIndex,
        createdAt: timestamp,
      });

      for (const [itemIndex, item] of category.items.entries()) {
        await db.insert(menuItems).values({
          id: newId(),
          restaurantId,
          categoryId,
          name: item.name,
          description: item.description,
          priceCents: item.priceCents,
          imageUrl: null,
          dietaryTags: JSON.stringify(item.dietaryTags ?? []),
          isAvailable: item.isAvailable ?? true,
          sortOrder: itemIndex,
          createdAt: timestamp,
          updatedAt: timestamp,
        });
      }
    }
  }

  const itemCount = DATA.reduce(
    (total, entry) => total + entry.categories.reduce((sum, category) => sum + category.items.length, 0),
    0,
  );

  console.log(
    [
      '',
      `Seeded ${DATA.length} restaurants and ${itemCount} menu items into ${config.databaseFile}.`,
      '',
      'Demo accounts — all with the password: ' + DEMO_PASSWORD,
      '  customer@foodonthego.test   places orders',
      '  owner@foodonthego.test      owns all four restaurants',
      '  courier@foodonthego.test    picks up and delivers',
      '',
    ].join('\n'),
  );

  close();
};

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
