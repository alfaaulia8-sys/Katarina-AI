# Model Registry Metadata

Git stores model metadata and promotion evidence, not large trained model binaries.

Track items such as:

- model_id;
- version;
- artifact hash;
- feature/schema version;
- training dataset identity;
- validation metrics;
- promotion/rollback status.

Actual artifacts belong in a dedicated artifact store or deployment package.
