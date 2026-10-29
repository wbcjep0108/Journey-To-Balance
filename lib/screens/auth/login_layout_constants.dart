/// Shared layout constants for the login screen and its skeleton placeholder.
///
/// Both [LoginScreen] and [LogoutSkeleton] import these values so the two
/// layouts cannot drift apart.
library;

/// Logo badge size passed to [BrandMark].
const double kLoginLogoSize = 104;

/// Corner radius of the logo badge (matches `BrandMark` formula: size * 0.28).
const double kLoginLogoRadius = kLoginLogoSize * 0.28; // ≈ 29.12

/// Gap between the logo and the title text.
const double kLoginLogoTitleGap = 22;

/// Approximate width of the "Journey to Balance" title for the skeleton.
const double kLoginTitleSkeletonWidth = 200;

/// Height of the title text line (matches fontSize 28).
const double kLoginTitleHeight = 28;

/// Gap between title and tagline.
const double kLoginTitleTaglineGap = 7;

/// Approximate width of the tagline for the skeleton.
const double kLoginTaglineSkeletonWidth = 240;

/// Height of the tagline text line (matches fontSize 14).
const double kLoginTaglineHeight = 14;

/// Gap between tagline and the mode-toggle track.
const double kLoginTaglineToggleGap = 28;

/// Height of the Log in / Sign up toggle track.
const double kLoginToggleHeight = 56;

/// Corner radius of the toggle track.
const double kLoginToggleRadius = 28;

/// Gap between toggle and the first text field.
const double kLoginToggleFieldGap = 24;

/// Height of each text-input pill (email / password).
const double kLoginFieldHeight = 56;

/// Corner radius of text-input pills.
const double kLoginFieldRadius = 30;

/// Gap between the email field and the password field.
const double kLoginFieldFieldGap = 16;

/// Gap between the password hint row and the primary action button.
const double kLoginFieldButtonGap = 18;

/// Height of the primary filled button ("Log in" / "Create account").
const double kLoginPrimaryButtonHeight = 52;

/// Corner radius of the primary (and Google) button.
const double kLoginButtonRadius = 30;

/// Gap between primary button and the "or" divider row.
const double kLoginButtonDividerGap = 20;

/// Horizontal padding around the "or" label in the divider row.
const double kLoginDividerLabelPadding = 12;

/// Gap between the "or" divider row and the Google button.
const double kLoginDividerGoogleGap = 20;

/// Height of the Google sign-in button.
const double kLoginGoogleButtonHeight = 52;

/// Gap between the Google button and the help / terms line.
const double kLoginGoogleTermsGap = 14;

/// Approximate skeleton width of the first terms line.
const double kLoginTermsLine1Width = 210;

/// Approximate skeleton width of the second terms line.
const double kLoginTermsLine2Width = 160;

/// Height of each skeleton terms line.
const double kLoginTermsLineHeight = 8;

/// Gap between skeleton terms lines.
const double kLoginTermsLineGap = 7;

/// Max width of the centered content column.
const double kLoginMaxWidth = 440;

/// Horizontal + vertical padding of the scroll view.
const double kLoginPaddingH = 24;
const double kLoginPaddingTop = 28;
const double kLoginPaddingBottom = 24;

