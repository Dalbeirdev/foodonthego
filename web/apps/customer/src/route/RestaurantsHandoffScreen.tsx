import { Link, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, UtensilsCrossed } from 'lucide-react';
import { Card } from '@fotg/ui';
import './route.css';

/**
 * Where "Find food on this route" lands, until Restart Module 07 builds it.
 *
 * A real route with a real screen at the end of it, rather than a dead click or
 * a 404. It shows the two identifiers the handoff carried — the journey and the
 * chosen route — because that is the thing worth proving here: the CTA passes
 * authoritative references onward, and Module 07 will fetch everything else
 * from the server rather than being handed restaurant data by a previous
 * screen.
 *
 * It says plainly that the listing does not exist yet. A placeholder that looked
 * like an empty result would report "no restaurants near you" for a feature
 * that was never built, which is worse than saying nothing.
 */
export const RestaurantsHandoffScreen = () => {
  const { tripId = '' } = useParams();
  const [params] = useSearchParams();
  const routeId = params.get('route');

  return (
    <div className="route">
      <header className="route__head">
        <h1 className="route__title">Food on your route</h1>
        <Link className="route__back" to={`/trips/${tripId}`}>
          <ArrowLeft size={16} aria-hidden="true" /> Back to your route
        </Link>
      </header>

      <Card className="route__status">
        <div className="route__status-icon" aria-hidden="true">
          <UtensilsCrossed size={22} />
        </div>
        <h2 className="route__status-title">Not built yet</h2>
        <p className="route__status-sub">
          Finding restaurants along your route is the next thing we&rsquo;re building. Your journey
          and the route you chose are saved and ready for it.
        </p>

        <dl className="route__handoff">
          <div>
            <dt>Journey</dt>
            <dd>
              <code>{tripId}</code>
            </dd>
          </div>
          <div>
            <dt>Selected route</dt>
            <dd>
              <code>{routeId ?? 'none'}</code>
            </dd>
          </div>
        </dl>
      </Card>
    </div>
  );
};
