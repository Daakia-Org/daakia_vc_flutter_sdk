/// `data` of `GET v2.0/configuration/cdn-assets`: sound key → absolute URL.
class CdnAssetsModel {
  final Map<String, String> sounds;

  CdnAssetsModel({this.sounds = const {}});

  CdnAssetsModel.fromJson(Map<String, dynamic> json)
      : sounds = {
          if (json['sounds'] is Map)
            for (final entry in (json['sounds'] as Map).entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
        };

  Map<String, dynamic> toJson() => {'sounds': sounds};
}
