# frozen_string_literal: true

module Strands
  # Intervention system for modifying or blocking agent operations.
  # Handlers return typed actions (Proceed, Deny, Guide, Transform).
  module Interventions
    # Action classes (defined directly in Strands::Interventions namespace)
    autoload :Proceed, "strands/interventions/actions"
    autoload :Deny, "strands/interventions/actions"
    autoload :Guide, "strands/interventions/actions"
    autoload :Transform, "strands/interventions/actions"

    autoload :Handler, "strands/interventions/handler"
    autoload :Registry, "strands/interventions/registry"
  end
end
