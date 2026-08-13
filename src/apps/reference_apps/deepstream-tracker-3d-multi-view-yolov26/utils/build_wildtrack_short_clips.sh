#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Trims + downsamples the 7 raw WILDTRACK camera recordings (~35min @ 59.94fps
# each) down to a short, ~30fps clip suitable for fast iteration, instead of
# the full-length originals in datasets/wildtrack_7cam/.
#
# Duration defaults to 210s (3.5min): WILDTRACK's own ground-truth annotations
# (annotations_positions/*.json) end at frame index 1995 in the 10fps-extracted
# numbering = 199.5s, so 210s keeps a small margin while covering all 400
# annotated frames -- unlike a plain 60s clip, which would only cover ~30% of
# the ground truth (121/400 frames).
#
# Uses the same hardware H.264 encoder DeepStream itself uses (nvv4l2h264enc),
# not a software fallback, so output quality matches the source -- unlike an
# OpenCV/mp4v re-encode.
#
# Halving 59.94fps -> 29.97fps (30000/1001) is an exact 2:1 decimation (every
# other raw frame kept), not an arbitrary resample, so `videorate` drops frames
# deterministically rather than duplicating/interpolating.
#
# Usage:
#   ./build_wildtrack_short_clips.sh <src_dataset_dir> <dst_dataset_dir> [duration_seconds]
#   ./build_wildtrack_short_clips.sh ~/workspace/wildtrack/Wildtrack ../datasets/wildtrack_7cam_short 210

set -euo pipefail

SRC="${1:?Usage: $0 <src_dataset_dir> <dst_dataset_dir> [duration_seconds]}"
DST="${2:?Usage: $0 <src_dataset_dir> <dst_dataset_dir> [duration_seconds]}"
DURATION_S="${3:-210}"

OUT_FPS_NUM=30000
OUT_FPS_DEN=1001
NUM_BUFFERS=$(( DURATION_S * OUT_FPS_NUM / OUT_FPS_DEN ))

mkdir -p "$DST/videos"

for i in 1 2 3 4 5 6 7; do
    src_video="$SRC/cam${i}.mp4"
    dst_video="$DST/videos/Cam${i}.mp4"
    echo "Cam${i}: ${src_video} -> ${dst_video} (${DURATION_S}s @ ${OUT_FPS_NUM}/${OUT_FPS_DEN}fps, ${NUM_BUFFERS} frames)"
    gst-launch-1.0 -e \
        filesrc location="$src_video" ! decodebin ! nvvidconv ! videorate \
        ! video/x-raw,framerate=${OUT_FPS_NUM}/${OUT_FPS_DEN} \
        ! identity eos-after=${NUM_BUFFERS} \
        ! nvvidconv ! nvv4l2h264enc bitrate=8000000 ! h264parse ! qtmux \
        ! filesink location="$dst_video"
done

echo "Done. Videos written to $DST/videos/"
