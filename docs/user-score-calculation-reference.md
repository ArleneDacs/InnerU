# Company User Score Computation

This reference is only for a regular user who belongs to a company. It covers
the Daily Tracker, Goals/Todo, and Company Leaderboard.

## 1. Daily Tracker

The default activities are Call, Steps, Exercise, Meditation, Learning, and
Add Value. Every active activity has equal value.

```text
Daily Tracker Score = Completed Activities / Active Activities x 100
```

Example: Completing 4 of 6 activities gives `4 / 6 x 100 = 66.7%`.

Simple rules:

- Each activity is either complete or incomplete; there is no extra credit.
- If only four activities are active, each activity is worth 25%.
- Any positive recorded step count currently completes the Steps activity.
- Goals/Todo is separate and is not part of the Daily Tracker score.
- Each calendar date has its own Daily Tracker score.

## 2. Goals/Todo

### Everyday Goal

```text
Everyday Goal Score = Unique Completed Days / Total Goal Days x 100
```

The total includes both the start date and due date. A date can count only
once.

Example: Completing 7 days of a 10-day goal gives `70%`.

### Long Term Goal

The progress shown on the goal card is:

```text
With todo items:    Completed Todo Items / Total Todo Items x 100
Without todo items: Completed = 100%; Incomplete = 0%
```

For the standard Goals Score, a Long Term Goal contributes `100%` only when
it is fully completed on or before its due date. An incomplete or late goal
contributes `0%`.

This means the goal card can show partial progress, such as `75%`, while that
goal still contributes `0%` to the standard Goals Score until it is completed
on time.

### Total Goals Score

```text
Total Goals Score = Sum of All Goal Scores / Number of Goals
```

Every goal has equal weight, and the result is rounded to the nearest whole
percent.

Example: Goal scores of `70%`, `100%`, and `0%` produce
`(70 + 100 + 0) / 3 = 56.7%`, displayed as `57%`.

## 3. Company Leaderboard

```text
Overall Score = (Leaderboard Daily Tracker Score + Leaderboard Goal Score) / 2
```

The Daily Tracker and Goals components each make up 50% of the Overall Score.
For example, `80%` Daily Tracker and `0%` Goals gives `40%` Overall.

### If the company has no leaderboard period

```text
Leaderboard Daily Tracker Score =
    Sum of Saved Daily Scores / Number of Saved Days
```

A date with no saved tracker record is not included. A saved date with a `0%`
score is included.

The Leaderboard Goal Score is the average of these goal results:

- Everyday Goal: completed days divided by total goal days.
- Long Term Goal with todo items: completed items divided by total items.
- Long Term Goal without todo items: `100%` if completed on time; otherwise
  `0%`.

The leaderboard therefore gives partial credit for completed Long Term todo
items, even though the standard Goals Score waits for full completion.

Example:

```text
Saved Daily Scores = 100%, 50%, 0%
Daily Tracker Score = (100 + 50 + 0) / 3 = 50%
Leaderboard Goal Score = 80%
Overall Score = (50 + 80) / 2 = 65%
```

### If the company has a leaderboard period

The start and end dates are both included.

```text
Period Days = End Date - Start Date + 1

Period Daily Tracker Score =
    Sum of Daily Scores Inside the Period / All Period Days
```

Missing and future dates inside the period currently count as zero because
all period days remain in the divisor.

Only Goals/Todo that start inside the company period are included. Everyday
completed dates earn day credits, while a completed Long Term Goal earns up
to one day credit. Each goal's credits are divided by all period days, and the
included goal results are averaged.

The same final formula is then used:

```text
Period Overall Score =
    (Period Daily Tracker Score + Period Goal Score) / 2
```

Scores can look low near the start of a company period because the calculation
already divides by the full number of period days.

## 4. Ranking

- Users see only leaderboard members from their company.
- Higher Overall Scores rank first.
- Equal scores are ordered alphabetically; ranks remain `1, 2, 3, ...`.
- A group score is the sum of its members' Overall Scores, not an average.

## Quick Reference

```text
Daily Tracker = Completed Activities / Active Activities x 100
Everyday Goal = Unique Completed Days / Total Goal Days x 100
Long Term Progress = Completed Todo Items / Total Todo Items x 100
Total Goals = Sum of Goal Scores / Number of Goals
Leaderboard Overall = (Daily Tracker Component + Goal Component) / 2
```
