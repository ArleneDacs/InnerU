<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\ChatRoom;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class ChatController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $this->currentUser($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $rooms = ChatRoom::query()
            ->whereJsonContains('participants', (string) $user->id)
            ->orderByDesc('last_message_time')
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (ChatRoom $room) => $this->mapRoom($room, (string) $user->id));

        return response()->json(['rooms' => $rooms]);
    }

    public function show(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsRoom($user, $chatRoom)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        return response()->json(['room' => $this->mapRoom($chatRoom, (string) $user->id)]);
    }

    public function messages(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsRoom($user, $chatRoom)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $messages = ChatMessage::query()
            ->where('chat_room_id', $chatRoom->id)
            ->orderBy('client_timestamp')
            ->orderBy('created_at')
            ->get()
            ->map(fn (ChatMessage $message) => $this->mapMessage($message));

        return response()->json(['messages' => $messages]);
    }

    public function storeRoom(Request $request): JsonResponse
    {
        $user = $this->currentUser($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'id' => ['required', 'string', 'max:255'],
            'is_group_chat' => ['sometimes', 'boolean'],
            'coach_id' => ['nullable', 'string', 'max:255'],
            'coach_name' => ['nullable', 'string', 'max:255'],
            'user_id' => ['nullable', 'string', 'max:255'],
            'user_name' => ['nullable', 'string', 'max:255'],
            'group_name' => ['nullable', 'string', 'max:255'],
            'group_profile_pic' => ['nullable', 'string', 'max:2048'],
            'participants' => ['nullable', 'array'],
            'participant_names' => ['nullable', 'array'],
            'participant_profiles' => ['nullable', 'array'],
            'unread_counts' => ['nullable', 'array'],
            'last_read_at' => ['nullable', 'array'],
            'company_id' => ['nullable', 'string', 'max:255'],
            'company_code' => ['nullable', 'string', 'max:255'],
            'company_name' => ['nullable', 'string', 'max:255'],
        ]);

        $room = ChatRoom::updateOrCreate(
            ['id' => $validated['id']],
            [
                'is_group_chat' => (bool) ($validated['is_group_chat'] ?? false),
                'coach_id' => $validated['coach_id'] ?? null,
                'coach_name' => $validated['coach_name'] ?? null,
                'user_id' => $validated['user_id'] ?? null,
                'user_name' => $validated['user_name'] ?? null,
                'group_name' => $validated['group_name'] ?? null,
                'group_profile_pic' => $validated['group_profile_pic'] ?? null,
                'participants' => $validated['participants'] ?? [],
                'participant_names' => $validated['participant_names'] ?? [],
                'participant_profiles' => $validated['participant_profiles'] ?? [],
                'unread_counts' => $validated['unread_counts'] ?? [],
                'last_read_at' => $validated['last_read_at'] ?? [],
                'company_id' => $validated['company_id'] ?? null,
                'company_code' => $validated['company_code'] ?? null,
                'company_name' => $validated['company_name'] ?? null,
            ]
        );

        return response()->json(['room' => $this->mapRoom($room, (string) $user->id)]);
    }

    public function storeMessage(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsRoom($user, $chatRoom)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'sender_id' => ['required', 'string', 'max:255'],
            'sender_name' => ['required', 'string', 'max:255'],
            'message' => ['nullable', 'string', 'max:5000'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'sender_profile_pic' => ['nullable', 'string', 'max:2048'],
            'client_timestamp' => ['nullable', 'date'],
        ]);

        $message = DB::transaction(function () use ($chatRoom, $validated): ChatMessage {
            $message = ChatMessage::create([
                'id' => (string) Str::uuid(),
                'chat_room_id' => $chatRoom->id,
                'sender_id' => $validated['sender_id'],
                'sender_name' => $validated['sender_name'],
                'message' => trim((string) ($validated['message'] ?? '')),
                'image_url' => trim((string) ($validated['image_url'] ?? '')) ?: null,
                'sender_profile_pic' => trim((string) ($validated['sender_profile_pic'] ?? '')) ?: null,
                'timestamp' => now(),
                'client_timestamp' => isset($validated['client_timestamp'])
                    ? Carbon::parse($validated['client_timestamp'])
                    : now(),
            ]);

            $room = $chatRoom->refresh();
            $participants = array_values(array_filter(array_map(
                static fn ($value) => (string) $value,
                $room->participants ?? [],
            )));
            $unreadCounts = $room->unread_counts ?? [];
            $lastReadAt = $room->last_read_at ?? [];
            foreach ($participants as $participantId) {
                $unreadCounts[$participantId] = $participantId === $validated['sender_id']
                    ? 0
                    : ((int) ($unreadCounts[$participantId] ?? 0) + 1);
                $lastReadAt[$participantId] = $participantId === $validated['sender_id']
                    ? now()->toIso8601String()
                    : ($lastReadAt[$participantId] ?? null);
            }

            $room->update([
                'last_message' => $message->message ?: ($message->image_url ? 'Sent a photo' : ''),
                'last_message_time' => $message->timestamp,
                'last_sender_id' => $message->sender_id,
                'unread_counts' => $unreadCounts,
                'last_read_at' => $lastReadAt,
            ]);

            return $message;
        });

        return response()->json(['message' => $this->mapMessage($message)]);
    }

    public function markRead(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsRoom($user, $chatRoom)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $room = $chatRoom->refresh();
        $participants = array_values(array_filter(array_map(
            static fn ($value) => (string) $value,
            $room->participants ?? [],
        )));
        $unreadCounts = $room->unread_counts ?? [];
        $lastReadAt = $room->last_read_at ?? [];
        foreach ($participants as $participantId) {
            $unreadCounts[$participantId] = $participantId === (string) $user->id ? 0 : (int) ($unreadCounts[$participantId] ?? 0);
            if ($participantId === (string) $user->id) {
                $lastReadAt[$participantId] = now()->toIso8601String();
            }
        }

        $room->update([
            'unread_counts' => $unreadCounts,
            'last_read_at' => $lastReadAt,
        ]);

        return response()->json(['room' => $this->mapRoom($room->refresh(), (string) $user->id)]);
    }

    private function ownsRoom(?User $user, ChatRoom $room): bool
    {
        if ($user === null) {
            return false;
        }

        return in_array((string) $user->id, array_map('strval', $room->participants ?? []), true);
    }

    private function currentUser(Request $request): ?User
    {
        $user = $request->user();
        return $user instanceof User ? $user : null;
    }

    private function mapRoom(ChatRoom $room, string $viewerId): array
    {
        $unreadCounts = $room->unread_counts ?? [];

        return [
            'chatRoomId' => (string) $room->id,
            'isGroupChat' => (bool) $room->is_group_chat,
            'groupName' => $room->group_name,
            'groupProfilePic' => $room->group_profile_pic,
            'participants' => array_values(array_map('strval', $room->participants ?? [])),
            'participantNames' => $room->participant_names ?? [],
            'participantProfiles' => $room->participant_profiles ?? [],
            'unreadCounts' => $unreadCounts,
            'lastReadAt' => $room->last_read_at ?? [],
            'lastMessage' => $room->last_message,
            'lastMessageTime' => $room->last_message_time?->toIso8601String(),
            'lastSenderId' => $room->last_sender_id,
            'coachId' => $room->coach_id,
            'coachName' => $room->coach_name,
            'userId' => $room->user_id,
            'userName' => $room->user_name,
            'companyId' => $room->company_id,
            'companyCode' => $room->company_code,
            'companyName' => $room->company_name,
            'unreadCount' => (int) ($unreadCounts[$viewerId] ?? 0),
            'updatedAt' => $room->updated_at?->toIso8601String(),
        ];
    }

    private function mapMessage(ChatMessage $message): array
    {
        return [
            'id' => (string) $message->id,
            'senderId' => (string) $message->sender_id,
            'senderName' => $message->sender_name,
            'message' => $message->message ?? '',
            'imageUrl' => $message->image_url,
            'senderProfilePic' => $message->sender_profile_pic,
            'timestamp' => $message->timestamp?->toIso8601String(),
            'clientTimestamp' => $message->client_timestamp?->toIso8601String(),
        ];
    }
}
