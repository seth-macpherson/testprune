# frozen_string_literal: true

require 'lipgloss'

module Testprune
  module UI
    # Centralized style palette. All UI components pull from here so the visual
    # identity stays consistent and editable in one place.
    #
    # Colors degrade automatically when NO_COLOR=1 is set (lipgloss strips ANSI).
    module Styles
      # ── Color hex constants ──────────────────────────────────────────────────
      PURPLE  = '#7D56F4'   # brand / borders / interactive
      GREEN   = '#22C55E'   # HIGH confidence / success / safe
      AMBER   = '#F59E0B'   # MEDIUM confidence / warnings
      GRAY    = '#6B7280'   # LOW confidence
      RED     = '#EF4444'   # errors / unsafe removals
      EMERALD = '#10B981'   # scan complete / patch written
      META    = '#9CA3AF'   # subdued meta-text (kept by, covers, timestamps)
      DIM     = '#3D3D5C'   # decorators / separators
      TEXT    = '#E2E8F0'   # default body text

      # ── Pre-built reusable styles ────────────────────────────────────────────

      # Rounded box with purple border — used for command headers.
      HEADER_BOX = Lipgloss::Style.new
                                  .border(:rounded)
                                  .border_foreground(PURPLE)
                                  .padding(0, 1)

      # Rounded box with emerald border — used for success summaries.
      SUCCESS_BOX = Lipgloss::Style.new
                                   .border(:rounded)
                                   .border_foreground(EMERALD)
                                   .padding(0, 1)

      # Rounded box with purple border — used for report sections and savings.
      REPORT_BOX = Lipgloss::Style.new
                                  .border(:rounded)
                                  .border_foreground(PURPLE)
                                  .padding(0, 1)

      # Confidence badges
      HIGH_BADGE   = Lipgloss::Style.new.foreground(GREEN).bold(true)
      MEDIUM_BADGE = Lipgloss::Style.new.foreground(AMBER).bold(true)
      LOW_BADGE    = Lipgloss::Style.new.foreground(GRAY)

      # Inline text styles
      SAFE_LINE    = Lipgloss::Style.new.foreground(GREEN)
      UNSAFE_LINE  = Lipgloss::Style.new.foreground(RED).bold(true)
      META_TEXT    = Lipgloss::Style.new.foreground(META)
      DIM_TEXT     = Lipgloss::Style.new.foreground(DIM)
      PURPLE_TEXT  = Lipgloss::Style.new.foreground(PURPLE)
      GREEN_TEXT   = Lipgloss::Style.new.foreground(GREEN)
      AMBER_TEXT   = Lipgloss::Style.new.foreground(AMBER)
      ERROR_TEXT   = Lipgloss::Style.new.foreground(RED).bold(true)
      EMERALD_TEXT = Lipgloss::Style.new.foreground(EMERALD)
    end
  end
end
