<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class NotificationController extends Controller
{
    // Latest-N cap for the poll-friendly list endpoint, mirroring how other
    // per-user list endpoints in this app (e.g. ChatController) return a
    // full-but-bounded list for the client to diff on each ~3s poll rather
    // than paginating.
    private const LIST_LIMIT = 50;

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $notifications = Notification::query()
            ->where('user_id', (string) $user->id)
            ->orderByDesc('created_at')
            ->limit(self::LIST_LIMIT)
            ->get()
            ->map(fn (Notification $notification) => $this->payload($notification));

        $unreadCount = Notification::query()
            ->where('user_id', (string) $user->id)
            ->whereNull('read_at')
            ->count();

        return response()->json([
            'notifications' => $notifications,
            'unreadCount' => $unreadCount,
        ]);
    }

    public function markRead(Request $request, string $notification): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $record = Notification::query()->find($notification);
        if ($record === null) {
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        if ((string) $record->user_id !== (string) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_FORBIDDEN);
        }

        if ($record->read_at === null) {
            $record->read_at = now();
            $record->save();
        }

        return response()->json([
            'notification' => $this->payload($record->refresh()),
        ]);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        Notification::query()
            ->where('user_id', (string) $user->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['message' => 'All notifications marked read.']);
    }

    public function destroy(Request $request, Notification $notification): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if ((string) $notification->user_id !== (string) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_FORBIDDEN);
        }

        $notification->delete();

        return response()->json(['message' => 'Notification deleted.']);
    }

    // Client-driven notify-myself endpoint retained for the legacy
    // meditation/exercise/fasting streak flows. Step-goal awards are now
    // calculated from DailyTracker rows on the server, so accepting a
    // client-supplied Steps milestone here could create a duplicate.
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'milestone' => ['required', 'string', 'max:255'],
            'days' => ['required', 'integer', 'min:1'],
            'activity' => ['required', 'string', 'max:120'],
        ]);

        $days = (int) $validated['days'];
        $activity = trim((string) $validated['activity']);
        $milestone = trim((string) $validated['milestone']);

        if (strtolower($activity) === 'steps') {
            return response()->json([
                'message' => 'Step-goal milestones are created automatically.',
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $notification = Notification::createFor(
            (string) $user->id,
            'streak_milestone',
            sprintf('%d-day %s streak!', $days, $activity),
            sprintf('You hit the "%s" milestone: %d days of %s.', $milestone, $days, $activity),
            [
                'milestone' => $milestone,
                'days' => $days,
                'activity' => $activity,
            ],
        );

        return response()->json([
            'notification' => $this->payload($notification),
        ], Response::HTTP_CREATED);
    }

    private function payload(Notification $notification): array
    {
        return [
            'id' => (string) $notification->id,
            'userId' => (string) $notification->user_id,
            'type' => $notification->type,
            'title' => $notification->title,
            'body' => $notification->body,
            'data' => $notification->data,
            'readAt' => $notification->read_at?->toIso8601String(),
            'createdAt' => $notification->created_at?->toIso8601String(),
            'updatedAt' => $notification->updated_at?->toIso8601String(),
        ];
    }
}
