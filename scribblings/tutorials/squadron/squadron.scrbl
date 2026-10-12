#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia skia/gpu))
@(define-runtime-path atlas-source "atlas.rkt")
@(define-runtime-path model-source "model.rkt")
@(define-runtime-path drawing-source "scene.rkt")
@(define-runtime-path program-source "squadron.rkt")
@(define-runtime-path math-source "../support/sprite-math.rkt")

@title[#:tag "star-squadron"]{Star Squadron — Build a Galaga-Inspired Arcade Game}

@section[#:tag "finished-result"]{The Finished Game}

@(tutorial-figure
   (string-append
    "An arcade playfield shows an enemy formation, diving ships, projectiles, and the "
    "player below. The header displays score, wave number, and remaining lives.")
   (game-pict))

An enemy formation moves across the top of the screen. Individual ships break
away, dive toward the player, fire, and return to the formation. The player
moves left and right, shoots the attackers, and tries to survive successive
waves with three lives.

This is a compact game inspired by Galaga, with original geometric artwork and
its own title. It does not reproduce the original graphics, sounds, capture
mechanic, or complete stage progression.

@centered{@bold{Simulate a world. Turn its state into sprites. Draw them from one retained atlas.}}

Run the game from the repository root:

@verbatim{
racket scribblings/tutorials/squadron/squadron.rkt --renderer gpu
}

Use the arrow keys or A/D to move and hold Space to fire. The P key or Pause
button freezes play. The R key or Restart button starts a new game, including
after game over. Click the playfield to return keyboard focus after using a
control. The Close button and the window's close control both exit the game.

The game builds on the sprite-atlas techniques in
@tutorial-link["sprites"].
If drawing into a window and scheduling animation frames are new to you, start
with @tutorial-link["animation"].

@tutorial-entry["squadron"]

@section{Give Every Object a Cell}

@(tutorial-figure
   (string-append
    "A four-by-four atlas contains two player frames, two scout frames, two guard frames, "
    "two projectiles, six explosion frames, a shield, and a star. Numbered cells and "
    "checkerboard are guides.")
   (game-atlas-pict))

The atlas is 224 by 224 pixels, displayed here at 2x with nearest sampling.
As before, each 48-by-48 source rectangle is surrounded by a four-pixel gutter.
The checkerboard, numbered labels, and cell outlines are explanatory overlays,
not part of the texture.

Cells 0–1 animate the player. Cells 2–3 animate scouts, and cells 4–5 animate
armored guards. Cells 6–7 contain the player and enemy projectiles. Cells 8–13
contain six explosion frames. The final two cells provide a shield ring and
a decorative star for experiments.

The artwork is made with familiar Skia paths, polygons, circles, and paints:

@codeblock[(source-definition atlas-source 'make-game-atlas)]

The atlas is built once, before play begins. The first GPU frame uploads it;
later frames and restarts retain that same GPU image. Changing an animation
frame means selecting another source rectangle, not drawing into or uploading
the atlas again.

@section{Keep Game State Separate from Drawing}

The world contains the player position, score, lives, wave number, enemies,
shots, explosions, and timing counters. These are ordinary Racket values.
The GPU atlas belongs to the window, not the game state.

@codeblock[(source-definition model-source 'make-game)]

The simulation changes this world. The renderer only reads it. A resize, an
exposure event, or an extra paint callback therefore cannot create another
shot or move an enemy. Restart makes a fresh world without replacing the atlas.

The three game modes are @racket['playing], @racket['wave-clear], and
@racket['game-over]. Pause belongs to the window scheduler: it temporarily
stops simulation without replacing the current game mode.

@section{Move the Player and Fire}

@(tutorial-figure
   (string-append
    "Two player frames at twice their source size differ in their flame shapes. The "
    "projectile on the right is shown at its natural size.")
   (ship-pict))

The figure shows the two player frames at 2x, followed by the projectile at
its natural atlas size. The flame changes shape while the ship keeps the same
anchor at its center.

The keyboard handler remembers pressed keys. The simulation reads that state
at each step instead of depending on operating-system key-repeat speed:

@racketblock[
(define direction
  (- (if (or (held? 'right) (held? #\d)) 1 0)
     (if (or (held? 'left) (held? #\a)) 1 0)))
]

The player moves at 340 scene units per second and is clamped to the playfield.
Pressing both directions cancels movement. Losing focus clears held keys, so
an unobserved key release cannot leave the ship moving indefinitely.

A cooldown limits continuous fire:

@codeblock[(source-definition model-source 'fire-player!)]

The cooldown is measured in fixed simulation steps. Eighteen steps at 120
steps per second give 0.15 seconds between shots. Each shot stores position,
velocity, and which side fired it. It has no image of its own.

@section{Build and Animate a Formation}

@(tutorial-figure
   (string-append
    "The formation contains three rows of seven ships. Armored guards occupy the top row, "
    "and scouts occupy the lower two rows.")
   (fleet-pict))

The fleet has three rows of seven ships. The upper row contains armored guards;
the lower rows contain scouts. A guard requires two hits and awards 200 points.
A scout requires one hit and awards 100 points.

@codeblock[(source-definition model-source 'formation-position)]

The stable enemy identifier determines its row and column. Shared sinusoidal
motion moves the fleet sideways, while a smaller vertical motion gives it a
light bob. A destroyed enemy disappears without causing other ships to change
formation slots.

Sprite animation selects one of two atlas cells from the simulation tick:

@racketblock[
(define frame (modulo (quotient tick 12) 2))
]

Each frame lasts 0.1 seconds. This is an artwork animation, independent of the
formation's motion. Pausing simulation freezes both.

@section{Let an Enemy Dive}

@(tutorial-figure
   (string-append
    "Two mirrored dive paths and their sampled ships share a uniform scale. Each ship "
    "points along the displayed direction of motion toward the target selected at launch.")
   (dive-pict))

The two attack paths are mirror images. A single uniform scale reduces the
paths and sprites together, so each ship points along the displayed direction
of travel. The @racket[enemy-angle] function measures rotation from the
downward-facing artwork: zero degrees points down, and 180 points up.

When a dive begins, it captures the enemy's current position and the player's
current horizontal position. The target does not follow later player movement,
so the player can evade the attack.

@codeblock[(source-definition model-source 'begin-dive!)]

The descent follows a cubic Bézier path. Here, the cubic calculation produces
positions for the simulation; it is not a path sent to Skia for drawing:

@codeblock[(source-definition model-source 'dive-point)]

The @racket[enemy-angle] function turns the direction of movement into a
clockwise rotation for @racket[make-atlas-transform]. Keeping the sprite's
nose aligned with its velocity makes the dives easy to follow.

@codeblock[(source-definition drawing-source 'enemy-angle)]

The dive takes 288 simulation steps, or 2.4 seconds, and ends below the
playfield. The enemy then re-enters from above and follows a 1.2-second return
segment toward its moving formation slot. The offscreen bottom-to-top jump is
intentional. A later wave launches attacks more frequently, with a lower bound
on the interval.

The complete @racket[enemy-position] function handles formation, descent, and
return using those same data:

@codeblock[(source-definition model-source 'enemy-position)]

@section{Advance in Small, Bounded Steps}

The shared host measures elapsed time, but the simulation always receives the
same 1/120-second step. It can perform several simulation steps before drawing
one frame, or simply redraw without stepping at all.

@codeblock[(source-definition math-source 'advance-clock)]

The host accepts at most 0.1 seconds of elapsed time per update and runs at most
12 steps. Excess wall time is discarded rather than queued indefinitely.
Under severe load the game can slow relative to real time. That trade-off is
preferable here to an unresponsive window trying to catch up after a long stall.

No simulation function reads the system clock or chooses random values. Starting
from the same world and supplying the same key state at each step produces the
same sequence of states. Live keyboard timing is still affected by GUI event
scheduling; a replay system would need to record inputs against simulation ticks.

@section{Hit Objects, Not Pixels}

@(tutorial-figure
   (string-append
    "The left projectile segment crosses an enemy hit circle. The right segment passes 45 "
    "illustration units from its center and misses the 38-unit circle. Collision bounds "
    "need not match opaque sprite pixels.")
   (collision-pict))

The left cyan segment crosses the hit circle; the right segment passes
45 illustration units from its center, outside the 38-unit radius. Both
enemies are shown at 2x, so that radius corresponds to the game's 19-unit
enemy radius.
The amber circles represent collision bounds, not the exact sprite outline.

The game uses simple circular hit regions, not the exact opaque pixels in each
sprite. This keeps the rules independent of the artwork and avoids reading
texture pixels back from the GPU.

For a fast projectile, checking only its new position could miss a target it
crossed between updates. The helper tests the traveled segment against a circle:

@codeblock[(source-definition model-source 'swept-hit?)]

@squadron-interaction[
(swept-hit? 10 200 10 0 10 100 8)
(swept-hit? 40 200 40 0 10 100 8)
]

The nearest point on the segment determines whether it enters the hit radius.
The enemy circle is evaluated at the current simulation step; this is not a
full continuous-collision solver for two moving shapes.

A player shot is consumed by its first matching enemy in list order. It cannot
score twice or destroy two overlapping targets. Enemy shots are consumed on
contact with the player. Losing a life grants a two-second shield, preventing
several simultaneous hits from removing all lives at once. The ship flashes
while that shield is active.

@section{Animate an Explosion Without Changing the Texture}

@(tutorial-figure
   (string-append
    "Six explosion cells appear in playback order. A growing ring and fading sparks "
    "progress across the atlas frames without modifying the texture during play.")
   (explosion-pict))

The six explosion cells are shown in playback order at 1.5x with nearest
sampling. The growing ring and fading sparks were rendered into the atlas
at startup. The game only selects the appropriate cell:

@racketblock[
(+ 8 (min 5 (quotient (blast-age effect) 8)))
]

Each cell lasts eight simulation steps. After 48 steps, or 0.4 seconds, the
explosion is removed. All explosions share the same six cells; many explosions
do not require many textures.

@section{Turn the World into a Sprite Batch}

The renderer creates a list of entries containing a cell index, position,
angle, and scale. This list does not own native resources:

@codeblock[(source-definition drawing-source 'game-sprites)]

The draw function converts those entries into transforms and source rectangles,
then submits them in one @racket[draw-atlas] call. Enemy sprites, the player,
projectiles, and explosions all select from the same image. Their list order
controls which sprites appear on top.

@codeblock[(source-definition drawing-source 'draw-game)]

The starfield, score panel, and text are separate Skia drawings. The atlas call
batches the sprites; it does not determine the driver's hardware draw-call count.

@section{Keep Score, Clear Waves, and Restart}

The simulation removes destroyed enemies, awards points, and creates explosions.
When the fleet becomes empty, it clears remaining shots and enters
@racket['wave-clear] for 180 steps. A new fleet then appears with the next wave
number. Score and remaining lives carry forward.

After the last life is lost, @racket['game-over] freezes simulation and displays
a restart prompt. The game displays these messages between waves and after
losing the last life:

@(tutorial-figure
   (string-append
    "The wave-clear message announces an incoming squadron. The game-over message asks "
    "the player to press R or click Restart after the last life is lost.")
   (game-states-pict))

Restart creates a new world while retaining the atlas and presenter. The upload
counter remains one.

The complete update function makes those state transitions explicit:

@codeblock[(source-definition model-source 'step-game!)]

@section{Run on CPU or GPU}

The default mode selects Metal on macOS, Direct3D 12 on Windows x64, or OpenGL
on Linux with a compatible graphical desktop. The same game can explicitly use
the CPU instead:

@verbatim{
racket scribblings/tutorials/squadron/squadron.rkt --renderer raster
}

CPU mode uses the original atlas and copies a completed Skia surface for GUI
presentation. GPU mode uses the retained GPU image and presents GPU frames
without an explicit per-frame pixel readback. Neither mode moves collision
checking or game logic onto the GPU.

The host fits the 640-by-760 scene into the window without stretching it.
GPU backing scale is applied before that viewport transform. Resizing does not
change the simulation's coordinates or recreate the atlas.

A selected but unavailable GPU raises an error rather than silently switching
to CPU rendering. Both modes still require a graphical session to open a window.

@section[#:tag "try-it"]{Try It}

Try moving the player after an enemy launches its dive. The captured target
should remain unchanged. Then pause, resize the window, and resume: none of
those operations should upload another atlas.

Try giving scouts two hit points, reducing the fire cooldown, or changing the
formation spacing. Change one rule at a time. The model tests can check the
new behavior without opening a window.

Try replacing one sprite drawing while keeping its anchor and source rectangle.
The movement and collision code should not need to change. A next experiment
could use the spare star cell for a collectible bonus.

@section[#:tag "next-steps"]{Where to Go From Here}

The game combines input, bounded fixed-step simulation, atlas animation, and batched drawing.
It is not a general game engine. Sound, replay recording, level scripting, and controller input
are possible extensions. Keep the same resource rule: upload for a context, reuse across its
frames, and release the atlas before closing that context.

@tutorial-next["squadron"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["squadron"]

The entry point, simulation, artwork, and renderer are separate files. The
window and GPU texture helpers under @filepath{../support/} are shared with
the @tutorial-link["sprites"] example. They are
example support code, not part of the Skia API.

The @command-text["--snapshot picture.png"] option saves one game frame as a PNG without
opening a window. Snapshot rendering uses the CPU.

@subsection{The Entry Point}
@codeblock[(file->string program-source)]

@subsection{The Atlas Artwork}
@codeblock[(file->string atlas-source)]

@subsection{The Game Model}
@codeblock[(file->string model-source)]

@subsection{The Renderer}
@codeblock[(file->string drawing-source)]
