# Canonical feature of select-estate-live-observation, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/20-select-estate-live-observation.dsl; host/serve.py at a57ebba, read from the code and not
# run; estate-live-observation-declared.feature (approved 2026-11-01); the record estate-live-observation-hosted.feature.

@project:sfx-api
@capability:select-estate-live-observation
@status:proposed-for-review
Feature: The run a subscriber follows is chosen by its declaration
  As someone following one run on the channel
  I want the run, and the frames that are its, chosen by the declared selection
  So that following a run means what the selection declares, and the facade adds no rule of its own

  Rule: The selection chooses the run, and the facade writes what it chose

    @approved:2026-11-01
    @status:installed
    Scenario: A followed run is chosen by select-estate-live-observation
      When a subscription selects a run
      Then the facade calls select-estate-live-observation with the selection and the retained windows, newest first
      And it writes only the chosen window's frames
      And for run=next it calls select again when a window opens
      # Word for word from estate-live-observation-declared.feature.

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: The facade's own observation meaning is removed
      Then host/serve.py holds no run window, graph or selection rule
      And the uncommitted run windows, graph detection and selection in host/serve.py are taken out
      # Word for word from estate-live-observation-declared.feature. host/serve.py:748-749 still decide which frames are
      # the chosen window's: a frame whose execution is the window's run and whose position lies between the window's
      # start and end. declarations/19 (authored 2026-11-02) now names, in each frame's window effect, the window the
      # frame belongs to, so the facade writes the frames that name the chosen window and applies no rule of its own.

    @status:installed
    Scenario: A selection that answers no window waits for the next window
      When select-estate-live-observation answers no window
      Then the subscription writes no run frame until a frame opens a window
      And the facade then calls select again
      # host/serve.py:293-303, 740-751, as the approved run=next step does.

    @status:not-built
    @finding:fallback
    Scenario: A selection whose delivery fails ends the subscription
      When the delivery of select-estate-live-observation fails
      Then the subscription ends
      And the host log names the failure
      # host/serve.py:293-303 take a failed delivery as no window, so the subscriber waits without knowing why.
