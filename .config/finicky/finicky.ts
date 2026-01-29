import type { FinickyConfig } from "/Applications/Finicky.app/Contents/Resources/finicky.d.ts";

export default {
    defaultBrowser: (url) => ({
        name: "Waterfox",
        args: ["--new", "--args", "-P", "default", url.toString()],
    }),
    handlers: [
        {
            match: (_url: URL, { opener }) => {
                console.log("opener:", opener);
                return opener?.name.includes("Slack") || false;
            },
            browser: (url) => ({
                name: "Waterfox",
                args: ["--new", "--args", "-P", "Work", url.toString()],
            }),
        },
    ],
} satisfies FinickyConfig;
