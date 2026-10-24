# 24-hour hackathon task ownership

| Owner | Folder | Deliver first | Deliver next |
|---|---|---|---|
| Backend | `backend/`, `docs/UDP_PROTOCOL.md` | synthetic UDP sender + Godot round-trip | webcam tracking, calibration, flick accuracy, beatmap draft |
| Godot gameplay | `frontend/`, `beatmaps/` | test screen receives synthetic UDP and keyboard fallback | beat timing, obstacles, hits, vibe meter, end screen |
| Design & graphics | `assets/` | rough hand, gull, wave and beach placeholders | polished sprites, animation, HUD palette |
| Presentation | `presentation/`, later `README.md` | pitch narrative and capture requirements | demo recording, submission screenshots, Devpost draft |

## Git workflow (keep it simple)
- All four developers clone the same repo.
- Create branches: `backend/tracking`, `frontend/gameplay`, `art/assets`, `presentation/pitch`.
- Don't commit directly to `main`. Open PRs; merge after a quick smoke test.
- Communicate immediately if changing `docs/UDP_PROTOCOL.md`, `beatmaps/demo.json`, or Godot autoload paths.
- If collaborating in one room, the fastest first checkpoint is Godot displaying synthetic `L UP`, `R DOWN` from `python -m backend.send_test`.
- Avoid large nonessential video/audio binaries in Git; use Git LFS or external links if needed.
