# Roadmap

Ideas being considered for upcoming versions. Nothing here is a promise or has a date. New features ship turned off and are switched on remotely once they are ready.

Have an idea? Open a [feature request](https://github.com/pablots25/ft_ham/issues/new?template=feature_request.yml).

## Decoding

- [ ] Optionally save receive slots as audio, so a decoder change can be measured against real recordings before a release.
- [ ] Regression test corpus built from those recordings: decodes that must appear, and false decodes that must not.

## Diagnostics

- [ ] Export a diagnostics report from Settings (app version, audio route, CAT state, recent logs with callsigns redacted) to attach to a bug report.

## Waterfall

- [ ] Slot lines with the UTC start time, even and odd slots marked, and your own transmit slot shaded.
- [ ] Long press on a trace to decode that slot again with the deep decoder.
- [ ] A noise floor that follows the radio's AGC, so weak signals next to a strong one stay visible.
- [ ] Accessibility and Dynamic Type improvements for the waterfall overlay.

## Decode list

- [ ] An optional split layout on iPad and in landscape: band activity on one side, stations calling you and your own transmissions on the other.

## Radios

- [ ] CAT control over the network without rigctld, starting with radios that offer LAN or Wi-Fi control.
