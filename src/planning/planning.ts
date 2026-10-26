export type WorkWindow = { day: number; start: string; end: string };

export type ParsedCostRow = {
  occurredOn: string;
  category: 'USAGE' | 'SUBSCRIPTION';
  amountMinor: number;
  currency: string;
  description: string;
};

const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function isValidTimezone(timezone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone });
    return true;
  } catch {
    return false;
  }
}

export function minutesOf(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

export function isWithinWorkWindows(now: Date, timezone: string, windows: WorkWindow[]): boolean {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? '';
  const day = weekdays.indexOf(get('weekday'));
  const current = Number(get('hour')) * 60 + Number(get('minute'));
  return windows.some((window) => (
    window.day === day && current >= minutesOf(window.start) && current < minutesOf(window.end)
  ));
}

function splitCsvLine(line: string): string[] {
  const cells: string[] = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quoted) {
      if (char === '"' && line[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        cell += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ',') {
      cells.push(cell.trim());
      cell = '';
    } else {
      cell += char;
    }
  }
  cells.push(cell.trim());
  return cells;
}

// Expected header: date,category,amount,currency,description. Amounts are decimal strings.
export function parseCostCsv(csv: string): { rows: ParsedCostRow[]; errors: string[] } {
  const lines = csv.split(/\r?\n/).filter((line) => line.trim() !== '');
  const rows: ParsedCostRow[] = [];
  const errors: string[] = [];
  if (lines.length === 0) {
    return { rows, errors: ['CSV jest pusty.'] };
  }
  const header = splitCsvLine(lines[0]).map((cell) => cell.toLowerCase());
  const expected = ['date', 'category', 'amount', 'currency', 'description'];
  if (expected.some((name, index) => header[index] !== name)) {
    return { rows, errors: [`Nagłówek musi być: ${expected.join(',')}`] };
  }
  lines.slice(1).forEach((line, offset) => {
    const lineNumber = offset + 2;
    const [date, category, amount, currency, description] = splitCsvLine(line);
    const upperCategory = (category ?? '').toUpperCase();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? '') || Number.isNaN(Date.parse(`${date}T00:00:00Z`))) {
      errors.push(`Linia ${lineNumber}: niepoprawna data.`);
    } else if (upperCategory !== 'USAGE' && upperCategory !== 'SUBSCRIPTION') {
      errors.push(`Linia ${lineNumber}: kategoria musi być USAGE lub SUBSCRIPTION.`);
    } else if (!/^\d{1,9}(\.\d{1,2})?$/.test(amount ?? '')) {
      errors.push(`Linia ${lineNumber}: niepoprawna kwota.`);
    } else if (!/^[A-Za-z]{3}$/.test(currency ?? '')) {
      errors.push(`Linia ${lineNumber}: niepoprawna waluta.`);
    } else {
      rows.push({
        occurredOn: date,
        category: upperCategory,
        amountMinor: Math.round(Number(amount) * 100),
        currency: currency.toUpperCase(),
        description: (description ?? '').slice(0, 200),
      });
    }
  });
  return { rows, errors };
}
