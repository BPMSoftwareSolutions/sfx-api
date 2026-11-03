# Canonical feature of capture-estate-live-observation-facts, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/22-capture-estate-live-observation-facts.dsl; host/serve.py at a57ebba, read from the code and
# not run; estate-live-observation.feature and estate-live-observation-declared.feature (approved 2026-11-01).

@project:sfx-api
@capability:capture-estate-live-observation-facts
@provider:apply-declared-change
@status:proposed-for-review
Feature: A finished run's facts are captured into the estate
  As the owner of the estate
  I want every finished run's facts captured where the estate's activity is read
  So that Retained shows the runs this host executes, as it showed the legacy host's

  Rule: The facts of every completed run are captured

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: A finished execution's facts are captured
      When a run is completed
      Then the facade calls capture-estate-live-observation-facts with the execution and its events
      And it reports the answer when it is not CAPTURED
      # Word for word from estate-live-observation-declared.feature. host/serve.py never invokes it. At a57ebba no run
      # directive named it; declarations/11 (authored 2026-11-02) names it as the run's facts, unpublished.

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: A finished run appears in Retained
      When a run completes
      Then its admission, and its return or failure, appear in the estate activity for its interval
      # Word for word from estate-live-observation.feature. README.md: the activity reader reads model.execution_fact,
      # and "runs this host executes are not captured there yet".
