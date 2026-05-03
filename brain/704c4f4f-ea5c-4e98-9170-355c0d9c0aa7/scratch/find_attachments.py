import asyncio
from database import init_supabase, get_supabase

async def find_attachments():
    await init_supabase()
    supabase = get_supabase()
    result = await supabase.table("complaints").select("id, attachment_urls, users(nickname)").not_.is_("attachment_urls", "null").execute()
    for r in result.data:
        if r['attachment_urls'] and len(r['attachment_urls']) > 0:
            print(f"ID: {r['id']}, Attachments: {r['attachment_urls']}, Nickname: {r.get('users', {}).get('nickname')}")
            break
    else:
        print("No reports with attachments found.")

if __name__ == "__main__":
    asyncio.run(find_attachments())
