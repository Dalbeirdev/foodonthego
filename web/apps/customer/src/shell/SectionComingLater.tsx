import { Card } from '@fotg/ui';
import '../home/home.css';

/**
 * What a section shows before its own restart module has built it.
 *
 * It is not a developer placeholder and does not name a module number: this is
 * production text a customer can meet. It says what the section is for and that
 * there is nothing in it yet, which is true and useful — "Restart Module 07
 * will repair this" is neither.
 *
 * The route is real and guarded, so navigation is never dead: every tab
 * answers, the URL is bookmarkable, and back behaves. What arrives later is
 * content, not the route.
 */
export const SectionComingLater = ({
  title,
  description,
}: {
  readonly title: string;
  readonly description: string;
}) => (
  <div className="home">
    <header className="home__greeting">
      <h1 className="home__greeting-title">{title}</h1>
    </header>
    <Card>
      <p className="home__card-line">{description}</p>
    </Card>
  </div>
);
