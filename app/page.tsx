import Link from "next/link";

export default function Home() {
    return (
        <div className="flex flex-col items-center justify-center min-h-screen py-2 bg-gray-50">
            <main className="flex flex-col items-center justify-center w-full flex-1 px-20 text-center">
                <h1 className="text-6xl font-bold text-gray-900">
                    Welcome to <span className="text-blue-600">LeadsRadar</span>
                </h1>
                <p className="mt-3 text-2xl text-gray-600">
                    AI-Powered Lead Generation & Outreach
                </p>

                <div className="flex flex-wrap items-center justify-around max-w-4xl mt-6 sm:w-full">
                    <div className="p-6 mt-6 text-left border w-96 rounded-xl hover:text-blue-600 focus:text-blue-600">
                        <h3 className="text-2xl font-bold">Client App &rarr;</h3>
                        <p className="mt-4 text-xl">
                            Log in to your dashboard to manage leads and API keys.
                        </p>
                        <div className="mt-6 flex space-x-4">
                            <Link
                                href="/login"
                                className="px-6 py-3 text-white bg-blue-600 rounded-lg hover:bg-blue-700"
                            >
                                Login
                            </Link>
                            <Link
                                href="/signup"
                                className="px-6 py-3 text-blue-600 bg-white border border-blue-600 rounded-lg hover:bg-blue-50"
                            >
                                Sign Up
                            </Link>
                        </div>
                    </div>
                </div>
            </main>
        </div>
    );
}
