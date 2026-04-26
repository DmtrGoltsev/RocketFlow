interface RetroListItem {
  title: string;
  body: string;
}

interface RetroListProps {
  items: RetroListItem[];
}

export function RetroList({ items }: RetroListProps) {
  return (
    <ul className="retro-list">
      {items.map((item) => (
        <li key={item.title} className="retro-list__item">
          <strong>{item.title}</strong>
          <span className="muted">{item.body}</span>
        </li>
      ))}
    </ul>
  );
}
