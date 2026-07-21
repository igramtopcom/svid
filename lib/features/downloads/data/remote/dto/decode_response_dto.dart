// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'decode_response_dto.freezed.dart';
part 'decode_response_dto.g.dart';

@freezed
class DecodeResponseDto with _$DecodeResponseDto {
  const factory DecodeResponseDto({
    @JsonKey(name: 'download_url') required String downloadUrl,
  }) = _DecodeResponseDto;

  factory DecodeResponseDto.fromJson(Map<String, dynamic> json) =>
      _$DecodeResponseDtoFromJson(json);
}
