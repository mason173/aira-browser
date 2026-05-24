import { useCallback, useEffect, useRef, useState } from 'react';
import { useDocumentVisibility } from '@/hooks/useDocumentVisibility';

export function formatClockTimeValue(now: Date, is24Hour: boolean, showSeconds: boolean): string {
  let hours = now.getHours();
  const minutes = now.getMinutes().toString().padStart(2, '0');
  const seconds = now.getSeconds().toString().padStart(2, '0');

  if (!is24Hour) {
    hours = hours % 12;
    hours = hours ? hours : 12;
    return showSeconds ? `${hours}:${minutes}:${seconds}` : `${hours}:${minutes}`;
  }

  const hoursStr = hours.toString().padStart(2, '0');
  return showSeconds ? `${hoursStr}:${minutes}:${seconds}` : `${hoursStr}:${minutes}`;
}

export function useClock(is24Hour: boolean, showSeconds: boolean, _language: string, _showLunar = true) {
  const initialNow = new Date();
  const isDocumentVisible = useDocumentVisibility();
  const [time, setTime] = useState(() => formatClockTimeValue(initialNow, is24Hour, showSeconds));
  const [date, setDate] = useState(initialNow);
  const calendarDayKeyRef = useRef('');

  useEffect(() => {
    let timer: number | null = null;

    const updateTime = () => {
      setTime(formatClockTimeValue(new Date(), is24Hour, showSeconds));
    };

    updateTime();

    if (!isDocumentVisible) {
      return;
    }

    const scheduleNextTick = () => {
      const stepMs = showSeconds ? 1000 : 60_000;
      const now = Date.now();
      const delay = stepMs - (now % stepMs) + 8;
      timer = window.setTimeout(() => {
        updateTime();
        scheduleNextTick();
      }, Math.max(16, delay));
    };

    scheduleNextTick();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [is24Hour, isDocumentVisible, showSeconds]);

  useEffect(() => {
    let timer: number | null = null;

    const updateCalendar = (force = false) => {
      const now = new Date();
      const dayKey = `${now.getFullYear()}-${now.getMonth()}-${now.getDate()}`;
      if (force || dayKey !== calendarDayKeyRef.current) {
        calendarDayKeyRef.current = dayKey;
        setDate(now);
      }
    };

    updateCalendar(true);

    if (!isDocumentVisible) {
      return;
    }

    const scheduleNextCalendarTick = () => {
      const now = new Date();
      const nextMidnight = new Date(now);
      nextMidnight.setHours(24, 0, 0, 32);
      const delay = nextMidnight.getTime() - now.getTime();
      timer = window.setTimeout(() => {
        updateCalendar(true);
        scheduleNextCalendarTick();
      }, Math.max(1000, delay));
    };

    scheduleNextCalendarTick();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [isDocumentVisible]);

  return { time, date, lunar: '' };
}

export function useClockTime(is24Hour: boolean, showSeconds: boolean) {
  const isDocumentVisible = useDocumentVisibility();
  const [time, setTime] = useState(() => formatClockTimeValue(new Date(), is24Hour, showSeconds));

  const updateTime = useCallback(() => {
    setTime(formatClockTimeValue(new Date(), is24Hour, showSeconds));
  }, [is24Hour, showSeconds]);

  useEffect(() => {
    let timer: number | null = null;

    updateTime();

    if (!isDocumentVisible) {
      return;
    }

    const scheduleNextTick = () => {
      const stepMs = showSeconds ? 1000 : 60_000;
      const now = Date.now();
      const delay = stepMs - (now % stepMs) + 8;
      timer = window.setTimeout(() => {
        updateTime();
        scheduleNextTick();
      }, Math.max(16, delay));
    };

    scheduleNextTick();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [isDocumentVisible, showSeconds, updateTime]);

  return time;
}

export function useClockDate(_language: string, _showLunar = true) {
  const initialNow = new Date();
  const isDocumentVisible = useDocumentVisibility();
  const [date, setDate] = useState(initialNow);
  const calendarDayKeyRef = useRef('');

  useEffect(() => {
    let timer: number | null = null;

    const updateCalendar = (force = false) => {
      const now = new Date();
      const dayKey = `${now.getFullYear()}-${now.getMonth()}-${now.getDate()}`;
      if (force || dayKey !== calendarDayKeyRef.current) {
        calendarDayKeyRef.current = dayKey;
        setDate(now);
      }
    };

    updateCalendar(true);

    if (!isDocumentVisible) {
      return;
    }

    const scheduleNextCalendarTick = () => {
      const now = new Date();
      const nextMidnight = new Date(now);
      nextMidnight.setHours(24, 0, 0, 32);
      const delay = nextMidnight.getTime() - now.getTime();
      timer = window.setTimeout(() => {
        updateCalendar(true);
        scheduleNextCalendarTick();
      }, Math.max(1000, delay));
    };

    scheduleNextCalendarTick();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [isDocumentVisible]);

  return { date, lunar: '' };
}
