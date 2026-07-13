
export enum WidthBreakpoint {
  XS = 'xs',
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl',
  XXL = 'xxl'
}

export enum DialogType {
  NORMAL,
  SHEET,
  FULL_SCREEN
}

export enum TextType {
  PLAIN,
  LINK,
  ACTION
}

export enum RouteName  {
  PRIVACY_CONSENT_H5 = 'PrivacyConsentH5Page',
  PRIVACY_CONSENT_H5_SHEET = 'PrivacyConsentH5SheetPage'
}

export interface PrivacyText {
  text: string;
  type: TextType;
  href?: string;
  onAction?: Callback<void>;
  color?: ResourceColor;
  fontSize?: Length;
  fontWeight?: FontWeight | number | string;
}

export type PrivacyDocument = PrivacyText[];
