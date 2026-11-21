# Player character — hands fix, M4 and extra animations

Branch `grok/player-hands-rifle` (Grok Bot). Only the player character files are changed.

## Hands fix (`assets/character/harlingen_character.glb`)
**What was wrong**
- The Mixamo `RightHand`/`LeftHand` and `*HandIndex1-4` joints sat 6.2 cm (right) / 6.7 cm (left) to the side of the wrist and hand mesh, outside the skin. Every wrist turn and finger curl pivoted around a point off the side of the hand, so the hands sheared and flopped.
- The index-finger joints didn't line up with the real knuckles: Index1 sat 2 cm inside the palm and Index3 was beyond the finger mesh.
- The finger skin weights were smeared. Fingertips were only about 15% on Index3, with about 20% still on Hand and 33% on Index1. Forearm weight reached the knuckles. As a result the fingers barely curled and stayed limp or open in the rifle clips.

**What changed** (the mesh, UVs, textures, materials and all other bones are byte-identical)
- Hand and Index joints moved onto the hand's centre line and onto the knuckle and finger joints (x = 0.746 / 0.782 / 0.806 / 0.828 m). The inverse bind matrices and every animation's translation keys for those bones were patched to match, so existing clips still play correctly.
- 1,048 right-hand and 1,129 left-hand vertices re-weighted:
  - smooth forearm→hand blend at the wrist
  - thumb rigid to Hand, because the Mixamo rig here has no thumb bones
  - the four fingers split Index1/2/3 at the knuckles
- The rig is Mixamo's index-finger-only skeleton (33 bones), so all four fingers curl together with the index chain.

## Animations (same GLB, glTF animations)
| Name | Source | Notes |
|---|---|---|
| Idle | `Bikini wipeout game/fixed/Idle.fbx` (Mixamo) | **Real.** Retargeted by bone name. Replaces the previous Idle. |
| Jump | `Bikini wipeout game/asset library/Running Jump (1).fbx` (Mixamo) | **Real.** Retargeted and made in place; the upward root motion is removed because physics does the jump. |
| Fall | `Bikini wipeout game/fixed/Falling Idle.fbx` (Mixamo) | **Real.** Retargeted. Plays after 0.45 s airborne. |
| StrafeLeft | `harlingen assets/Strafing.fbx` (Mixamo) | **Real.** Same clip as `Strafing`, made in place. |
| StrafeRight | StrafeLeft played backwards | **Derived.** Not mirrored, so the rifle stays in the right hand. |
| RifleIdle | WalkWithRifle frame 0 arms and spine + Idle legs and breathing | **Authored.** No rifle idle clip exists. |
| WalkWithRifle, Reloading, Walking, FastRun, Punching, Strafing | already in the repo (Mixamo) | unchanged apart from the hand-joint fix |

Retargeting maps each bone's world rotation change from the source rest T-pose onto this character's rest, corrected for facing (the source faces +Z and this rig faces −Z). Hips height is scaled by the hip-height ratio.

## M4
- `assets/weapons/m4/Modern_M4_LOD1.glb`: about 18k tris, with 2048² BaseColor/ORM/Normal textures extracted by Godot.
- Source: the user's own asset library, `OneDrive/Desktop/Asset Library/Modern_M4/Modern_M4_LOD1.glb` ("Modern M4 v3", 27 Oct 2026). It was built procedurally from scripts by Grok Bot for the user, so there are no third-party assets or licence terms.
- Attached in `PlayerCharacter.tscn`:
  - `VisualRoot/RifleAttachment` is a BoneAttachment3D on `mixamorig_RightHand`, using the external skeleton `CharacterModel/Armature/Skeleton3D`.
  - Under it, `M4Grip` (a fixed offset) holds the `M4` instance.
- The offset puts the pistol grip in the right palm and lines the handguard up with the left palm in the rifle clips. Measured in Godot, the left palm is 3 cm from the handguard in WalkWithRifle/RifleIdle and 4–5.5 cm in the strafes. During Reloading the left hand leaves to work the magazine.
- Real scale: 0.75 m long with the stock collapsed.
- Visible only in rifle stance (Q), while strafing (C / RMB) or during Reload (R).

## Controller / AnimationTree
- `RifleLocomotion` blends RifleIdle → WalkWithRifle. Before this change it used the unarmed Idle.
- The `Strafing` state is now a discrete BlendSpace1D, with StrafeLeft at −1 and StrafeRight at +1, driven by the A/D input.
- New `Jump` and `Fall` states with crossfades to and from Locomotion, RifleLocomotion and Strafing.
- No InputMap changes. The existing keys are Space (jump), C (strafe), R (reload) and Q (rifle stance).
