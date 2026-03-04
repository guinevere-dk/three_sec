# Trash Restore/Delete Regression Checklist

## Scope
- Library trash action UI (icon-only)
- Project trash action UI (icon-only)
- Restore routing to original folder/album
- Fallback routing when original folder/album is deleted

## Manual Scenarios

- [ ] Library: move a clip from a custom album to trash, restore it, verify it returns to original album
- [ ] Library: delete original album after moving clip to trash, restore clip, verify fallback to `일상`
- [ ] Library: in trash multi-select mode, verify only icon buttons are shown for restore/permanent delete
- [ ] Library: permanently delete selected clips from trash and verify files are removed

- [ ] Project: move a project from a custom folder to trash, restore it, verify it returns to original folder
- [ ] Project: delete original folder after moving project to trash, restore project, verify fallback to `기본`
- [ ] Project: in trash multi-select mode, verify only icon buttons are shown for restore/permanent delete
- [ ] Project: permanently delete selected projects from trash and verify metadata/file removal

- [ ] VlogScreen parity: repeat Project restore and fallback scenarios and verify same behavior as ProjectScreen

## Visual Consistency
- [ ] Trash action panel theme matches Library/Project bottom action theme (radius, shadow, icon-button style)
- [ ] No text label is shown for trash restore/permanent delete actions

