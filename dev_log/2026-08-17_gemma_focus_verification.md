# Developer Log: Gemma Multimodal Focus Verification & Pie Chart Alerts

**Date**: August 17, 2026  
**Topic**: Gemma 4-bit Vision Focus Auditor, Headless Screen Capture, Animated Pie Chart & Flashing Off-Task Alerts

---

## 1. Overview & Architecture

To help users stay strictly on task, Task Monitor integrates an intelligent vision-auditing pipeline powered by a lightweight **4-bit quantized Gemma model (`gemma:2b` / `gemma-e2b-q4`)** via local Ollama.

### Verification Lifecycle
1. **User Opt-In**: The AI focus auditor is disabled by default (`_isAiAuditEnabled = false`) to ensure zero background screenshots or inference until explicitly enabled via the on-bar magic icon (`Icons.auto_awesome`) or system tray menu.
2. **Screen Capture & Downscaling**: Native Linux screen capture tools (`gnome-screenshot`, `import -window root`, `grim`) take a snapshot of active desktop activity and downscale it to 768px JPEG, minimizing RAM usage and ensuring <50ms capture time.
3. **Structured VLM Prompting**: Sends base64 image data with a formatted prompt to the local Ollama REST endpoint (`/api/generate`) with `format: "json"`.
4. **Scoring & Visualization**:
   - Scores mapped to `FocusPieChart` (a 30px custom-painted animated arc):
     - **Green (`> 50%`)**: `#2E7D32` (Strong alignment with focus objective).
     - **Yellow (`20% - 50%`)**: `#F57F17` (Moderate / research alignment).
     - **Red (`< 20%`)**: `#D32F2F` (Off-task / distracted).
5. **Off-Task Flashing Alert**: When a score drops below `20%`, Task Monitor immediately triggers the prominent flashing red bar alert (`_triggerOffTaskAlert`), snapping the user's attention back to their goal.

---

## 2. Key Components Added

### `lib/services/screen_capture_service.dart`
- Multi-backend Linux capture (`gnome-screenshot`, ImageMagick `import`, `grim`, `scrot`).
- Automatic temporary file management and cleanup.
- Quality and dimension downscaling before base64 encoding.

### `lib/services/focus_verifier_service.dart`
- Direct async client targeting `http://127.0.0.1:11434/api/generate`.
- Robust JSON response parser extracting `match_percentage` (0–100) and `reason`.
- Automatic fallback and simulation support when local daemon is unreachable.

### `lib/widgets/focus_pie_chart.dart`
- Custom-painted compact pie chart / gauge with smooth cubic ease sweep animations.
- Hover tooltip displaying current score, status, and Gemma's explanation.
- Tap-to-refresh: tapping the pie chart triggers an immediate re-audit.

### `scripts/setup_ollama.sh`
- Verifies and initializes local Ollama daemon on port 11434.
- Pulls and verifies `gemma:2b`.
- Runs test probe generation.

---

## 3. Testing & Verification

- `test/focus_verifier_test.dart`: Validates classification thresholds (>50% green, 20-50% yellow, <20% red), boundary scores, and JSON parsing.
- `test/focus_pie_chart_test.dart`: Validates widget states (disabled, active, loading).
- `flutter test`: 12/12 unit and widget tests passing.
- `flutter analyze`: 0 issues found.
