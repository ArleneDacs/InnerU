import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

void main() {
  group('ImageStorageService.normalizeMediaUrl', () {
    test('keeps absolute urls and rewrites localhost to api base', () {
      expect(
        ImageStorageService.normalizeMediaUrl(
          'https://example.com/media/photo.jpg',
        ),
        'https://example.com/media/photo.jpg',
      );

      expect(
        ImageStorageService.normalizeMediaUrl(
          'http://localhost:4000/uploads/photo.jpg',
        ),
        'https://inneru-api.valenin.com/uploads/photo.jpg',
      );

      expect(
        ImageStorageService.normalizeMediaUrl(
          'http://inneru-api.valenin.com/uploads/photo.jpg',
        ),
        'https://inneru-api.valenin.com/uploads/photo.jpg',
      );
    });

    test('prefixes relative paths with the api base url', () {
      expect(
        ImageStorageService.normalizeMediaUrl('/uploads/photo.jpg'),
        'https://inneru-api.valenin.com/uploads/photo.jpg',
      );

      expect(
        ImageStorageService.normalizeMediaUrl('uploads/photo.jpg'),
        'https://inneru-api.valenin.com/uploads/photo.jpg',
      );
    });

    test('keeps loading placeholders intact', () {
      expect(ImageStorageService.normalizeMediaUrl('loading'), 'loading');
    });
  });

  group('ImageStorageService.normalizeCommunityMediaUrl', () {
    test('prefixes storage keys with the api storage url', () {
      expect(
        ImageStorageService.normalizeCommunityMediaUrl(
          'users/42/community-images/post.jpg',
        ),
        'https://inneru-api.valenin.com/storage/users/42/community-images/post.jpg',
      );

      expect(
        ImageStorageService.normalizeCommunityMediaUrl(
          '/storage/users/42/community-images/post.jpg',
        ),
        'https://inneru-api.valenin.com/storage/users/42/community-images/post.jpg',
      );
    });

    test('keeps absolute urls and rewrites localhost to api base', () {
      expect(
        ImageStorageService.normalizeCommunityMediaUrl(
          'http://localhost:4000/storage/users/42/community-images/post.jpg',
        ),
        'https://inneru-api.valenin.com/storage/users/42/community-images/post.jpg',
      );

      expect(
        ImageStorageService.normalizeCommunityMediaUrl(
          'http://inneru-api.valenin.com/storage/users/42/community-images/post.jpg',
        ),
        'https://inneru-api.valenin.com/storage/users/42/community-images/post.jpg',
      );
    });
  });
}
