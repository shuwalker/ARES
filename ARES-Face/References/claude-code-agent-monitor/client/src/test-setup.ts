/**
 * @file test-setup.ts
 * @description Test setup file for the client-side unit tests using Vitest and React Testing Library. This file configures the testing environment, including importing necessary libraries and performing cleanup after each test to ensure isolation between tests. The cleanup function from React Testing Library is called after each test to unmount components and clean up the DOM, preventing side effects from affecting other tests.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, beforeEach } from "vitest";
import "./i18n/index";
import i18n from "i18next";

// Force English locale for deterministic test assertions
// (LanguageDetector may pick up zh from the system environment)
beforeEach(() => {
  i18n.changeLanguage("en");
});

afterEach(() => {
  cleanup();
});
