Aura — selected hitapp design
Saved 19 October 2026

Open index.html in a browser to explore the design.
aura-source.html is the editable source; aura-preview.png is the visual reference.
Keep the selected Aura design and cursor bubble animation only.
All other motion studies were discarded at the user's request.

Direction
Performative UI is the main influence: near-black surfaces, violet/pink/blue
aurora light, dark glass panels, fine borders, and a rounded gradient composer.
A little HeyClicky personality comes from the glossy cursor and expressive face.
The cursor stays tiny: 24 px on the home screen and 28 px in action previews.

Cursor bubble
A small three-dot speech bubble sits just above the cursor. Tap the cursor to
replay its spring-like pop and staggered dot bounce. It also animates during
the working preview. Reduced Motion removes movement. Cursor tap target: 44 px.
The bubble pop and bouncing dots are the only retained animations. Cursor
movement, listening waves, completion bounce, glow motion and spinners are off.

Interactions
Try the microphone for a simulated voice draft, then review and send it.
Try a reminder for working, action approval and completion states.
Screenshot attachment uses sample context. All actions are simulated.

Implementation status
Implemented in native SwiftUI on 19 October 2026: dark aurora background,
glass presence card, real connection state, tiny cursor bubble and gradient
composer. Existing dictation review, attachment, Stop and settings are wired.
Requested Tapp gestures use saved access without repeated approval cards.
System permissions and other action-specific flows remain separate.
When implementing, retain existing dictation review, screenshot attachment,
approval, cancellation, connections, settings and phone-assistance flows.
Connect activity labels and animation to real app state; do not display a
connected status merely because a model endpoint is configured.

References
https://vorpus.github.io/performativeUI/
https://www.heyclicky.com/
