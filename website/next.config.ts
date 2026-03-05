import type { NextConfig } from "next";

const repository = process.env.GITHUB_REPOSITORY ?? "christopherkarani/Terra";
const repoName = repository.split("/")[1] ?? "Terra";
const isGitHubPagesBuild = process.env.NEXT_PUBLIC_GH_PAGES === "true";
const basePath = isGitHubPagesBuild ? `/${repoName}` : "";

const nextConfig: NextConfig = {
  ...(isGitHubPagesBuild
    ? {
        output: "export",
        trailingSlash: true,
        images: {
          unoptimized: true,
        },
        basePath,
        assetPrefix: basePath || undefined,
      }
    : {}),
};

export default nextConfig;
