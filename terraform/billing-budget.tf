data "google_billing_account" "main" {
  billing_account = var.billing_account_id
}

resource "google_billing_budget" "purple_lab_monthly" {
  billing_account = data.google_billing_account.main.id
  display_name    = "purple-lab-48271 monthly budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "25"
    }
  }

  # Alerts based on actual spend so far this month
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  # Warns based on GCP's own projection of where you're headed,
  # before you actually get there -- catches a runaway cost trend
  # early rather than after the fact.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # No explicit notification config below this line -- GCP's default
  # behavior emails everyone with Billing Account Administrator or
  # Billing Account User IAM roles automatically. Since you're the
  # project owner, this reaches you with zero extra setup.
}
