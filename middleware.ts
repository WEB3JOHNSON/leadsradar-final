import { type NextRequest, NextResponse } from 'next/server';
import { createServerClient } from '@supabase/ssr';
import { v4 as uuidv4 } from 'uuid';

export async function middleware(request: NextRequest) {
    // 1. Generate Request ID
    const requestHeaders = new Headers(request.headers);
    const requestId = uuidv4();
    requestHeaders.set('X-Request-ID', requestId);

    // 2. Refresh Supabase Session
    let supabaseResponse = NextResponse.next({
        request: {
            headers: requestHeaders,
        },
    });

    // Add Request ID to response headers
    supabaseResponse.headers.set('X-Request-ID', requestId);

    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            cookies: {
                getAll() {
                    return request.cookies.getAll();
                },
                setAll(cookiesToSet) {
                    cookiesToSet.forEach(({ name, value, options }) =>
                        request.cookies.set(name, value)
                    );

                    supabaseResponse = NextResponse.next({
                        request: {
                            headers: requestHeaders,
                        },
                    });

                    cookiesToSet.forEach(({ name, value, options }) =>
                        supabaseResponse.cookies.set(name, value, options)
                    );
                },
            },
        }
    );

    // This refreshes the session if needed
    await supabase.auth.getUser();

    // 3. Protected Routes Check
    if (request.nextUrl.pathname.startsWith('/dashboard')) {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) {
            return NextResponse.redirect(new URL('/login', request.url));
        }
    }

    return supabaseResponse;
}

export const config = {
    matcher: [
        /*
         * Match all request paths except for the ones starting with:
         * - _next/static (static files)
         * - _next/image (image optimization files)
         * - favicon.ico (favicon file)
         * Feel free to modify this pattern to include more paths.
         */
        '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
    ],
};
